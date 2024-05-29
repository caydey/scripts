#!/bin/sh

# Copyright (c) 2024 caydey
# 
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
# 
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
# 
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.


CONFIG_PATH="/root/tar-snapshot-config"

# DRY_RUN_FOLDER=/tmpdisk/tarsnap

function check_root() {
  if [ $UID -ne 0 ]; then
    echo "run script as root user"
    exit 1
  fi
}

function check_packages() {
  local REQUIRED_PACKAGES=(jq gpg aws zstd)
  local PACKAGE_NOT_FOUND=false
  for PACKAGE in "${REQUIRED_PACKAGES[@]}"; do
    if ! whereis "$PACKAGE" | grep -q "$PACKAGE: /"; then
      PACKAGE_NOT_FOUND=true
      echo "Executable: \"$PACKAGE\" not found"
    fi
  done
  if $PACKAGE_NOT_FOUND; then
    echo "Exiting due to missing packages"
    exit 1
  fi
}

function check_initialised() { # 1=CONFIG_PATH
  local CONFIG_PATH="$1"

  local FILES_CREATED=false # bool flag

  local INCLUDE_FILE="$CONFIG_PATH/include.list"
  if [[ ! -f "$INCLUDE_FILE" ]]; then
    echo "/home/*/Documents" > "$INCLUDE_FILE"
    FILES_CREATED=true
  fi

  local INJECT_FILE="$CONFIG_PATH/injectors.sh"
  if [[ ! -f "$INJECT_FILE" ]]; then
    echo "#!/bin/sh"                                                > "$INJECT_FILE"
    echo "# functions must start with \"inject_\""                  >> "$INJECT_FILE"
    echo "function inject_lsblk() { lsblk -OJ > "$1/lsblk.json"; }" >> "$INJECT_FILE"
    chmod +x "$INJECT_FILE"
    FILES_CREATED=true
  fi

  local SECRETS_FILE="$CONFIG_PATH/secrets.config"
  if [[ ! -f "$SECRETS_FILE" ]]; then
    echo "AWS_ACCESS_KEY_ID="       > "$SECRETS_FILE"
    echo "AWS_SECRET_ACCESS_KEY="   >> "$SECRETS_FILE"
    echo "AWS_DEFAULT_REGION="      >> "$SECRETS_FILE"
    echo "AWS_BUCKET_NAME="         >> "$SECRETS_FILE"
    echo "SECRET_MASTER_KEY="       >> "$SECRETS_FILE"
    echo "SECRET_MASTER_KEY_HINT="  >> "$SECRETS_FILE"
    FILES_CREATED=true
  fi

  if $FILES_CREATED; then
    echo "config files initialised at $CONFIG_PATH"
    echo "please review them before re-running this script"
    exit 1
  fi
}

function reviewSnapshot() { # 1=SNAPSHOT_OUTPUT
  SNAPSHOT_SIZE=$(du -h "$1" | awk '{ print $1 }')
  read -e -p "Upload Snapshot ($SNAPSHOT_SIZE)? [Y/n]: " yn
  if [[ "$yn" != "" ]] && [[ "$yn" != [Yy]* ]]; then
    echo "exiting"
    exit 1
  fi
}

function displayBucketInfo() {
  if [ -n "$DRY_RUN_FOLDER" ]; then
    echo "Using $DRY_RUN_FOLDER"
    return
  fi

  local BUCKET_FILE_LIST_SNAPSHOT_ONLY=$(echo "$BUCKET_FILE_LIST" | jq -r '[.Contents[]? | select(.Key | test("^[0-9]+-[0-9]+.[0-9]+.tar.[a-z]+.gpg"))]')

  local SNAPSHOT_COUNT=$(echo "$BUCKET_FILE_LIST_SNAPSHOT_ONLY" | jq -r 'length')

  if [ "$SNAPSHOT_COUNT" == "0" ]; then
    echo "First Snapshot"
  else
    local TOTAL_BUCKET_SIZE=$(echo "$BUCKET_FILE_LIST" | jq -r '[.Contents[]?.Size] | add' | numfmt --to=iec)
    local LAST_SNAPSHOT_SIZE=$(echo "$BUCKET_FILE_LIST_SNAPSHOT_ONLY" | jq -r "max_by(.LastModified) | .Size" | numfmt --to=iec)
    local LAST_SNAPSHOT_MODIFIED_RAW=$(echo "$BUCKET_FILE_LIST_SNAPSHOT_ONLY" | jq -r "max_by(.LastModified) | .LastModified")
    local LAST_SNAPSHOT_MODIFIED=$(date -d "$LAST_SNAPSHOT_MODIFIED_RAW" +'%Y/%m/%d %H:%M:%S')

    echo "Snapshots: $SNAPSHOT_COUNT ($TOTAL_BUCKET_SIZE)  Last: $LAST_SNAPSHOT_MODIFIED ($LAST_SNAPSHOT_SIZE)"
  fi
}

function encryptFile() { # 1=INPUT, 2=OUTPUT
  if [ ! -n "$SECRET_MASTER_KEY" ]; then
    echo "WARNING, ENCRYPTION KEY NOT SET, exiting..."
    exit 1
  fi

  printf "Encrypting $(basename "$1")..."
  gpg --symmetric --batch \
    --cipher-algo AES256 --compress-algo none \
    --passphrase "$SECRET_MASTER_KEY" \
    --output "$2" "$1"
  rm "$1"
  echo " Done"
}

function decryptFile() {
  gpg --decrypt --batch --quiet \
    --cipher-algo AES256 --compress-algo none \
    --passphrase "$SECRET_MASTER_KEY" \
    --output "$2" "$1"
}

function getBucketFileList() {
  if [ ! -n "$DRY_RUN_FOLDER" ]; then
    aws s3api list-objects-v2 --bucket "$AWS_BUCKET_NAME"
  fi
}

function getBucketFileListSnapshotOnly() {
  if [ ! -n "$DRY_RUN_FOLDER" ]; then
    echo "$1" | jq -r '[.Contents[]? | select(.Key | test("^[0-9]+-[0-9]+.[0-9]+.tar.[a-z]+.gpg"))]'
  fi
}

function downloadIndexSnar() { # 1=OUTPUT
  local OUTPUT="$1"

  if [ -n "$DRY_RUN_FOLDER" ]; then
    if [ -f "$DRY_RUN_FOLDER/index.snar.zst.gpg" ]; then
      local TMP_CMP_INDEX_SNAR="$TMP_FOLDER/index.snar.zst"
      decryptFile "$DRY_RUN_FOLDER/index.snar.zst.gpg" "$TMP_CMP_INDEX_SNAR"
      zstd --decompress  --quiet "$TMP_CMP_INDEX_SNAR" -o "$OUTPUT"
      rm "$TMP_CMP_INDEX_SNAR"
    else
      touch "$OUTPUT"
    fi
  else
    if echo "$BUCKET_FILE_LIST" | jq -r '.Contents[]? | .Key' | grep -q "index.snar.zst.gpg"; then
      local TMP_ENC_INDEX_SNAR="$TMP_FOLDER/index.snar.zst.gpg"
      local TMP_CMP_INDEX_SNAR="$TMP_FOLDER/index.snar.zst"
      aws s3api get-object --bucket $AWS_BUCKET_NAME --key "index.snar.zst.gpg" "$TMP_ENC_INDEX_SNAR" > /dev/null
      decryptFile "$TMP_ENC_INDEX_SNAR" "$TMP_CMP_INDEX_SNAR"
      zstd --decompress --quiet "$TMP_CMP_INDEX_SNAR" "$OUTPUT"
      rm "$TMP_ENC_INDEX_SNAR" "$TMP_CMP_INDEX_SNAR"
    else
      echo "index.snar.zst.gpg not found on bucket"
      touch "$OUTPUT"
    fi
  fi
}

function populateMasterExcludeFile() { # 1=MASTER_EXCLUDE_FILE, 2=CONFIG_PATH
  MASTER_EXCLUDE_FILE="$1"
  CONFIG_PATH="$2"
  touch "$MASTER_EXCLUDE_FILE"
  for excludeFile in "$CONFIG_PATH"/exclude*.list; do
    cat "$excludeFile" >> "$MASTER_EXCLUDE_FILE"
    echo >> "$MASTER_EXCLUDE_FILE"
  done
}

function populateMasterIncludeFile() { # 1=MASTER_INCLUDE_FILE, 2=CONFIG_PATH
  MASTER_INCLUDE_FILE="$1"
  CONFIG_PATH="$2"
  touch "$MASTER_INCLUDE_FILE"
  for includeFile in "$CONFIG_PATH"/include*.list; do
    cat "$includeFile" >> "$MASTER_INCLUDE_FILE"
    echo >> "$MASTER_INCLUDE_FILE"
  done
}

function getSnapshotName() {
  local SNAP_NUMBER=0
  if [ -n "$DRY_RUN_FOLDER" ]; then
    SNAP_NUMBER=$(ls -1 "$DRY_RUN_FOLDER" | grep -P "\d+-\d+.\d+.tar.\w+" | wc -l)
  else
    SNAP_NUMBER=$(echo "$BUCKET_FILE_LIST_SNAPSHOT_ONLY" | jq -r "length")
  fi
  echo "$(date +'%y%m%d-%H%M%S').$SNAP_NUMBER"
}

function uploadFile() { # 1=INPUT, 2=STORAGE_CLASS
  local INPUT="$1"
  local STORAGE_CLASS="$2"
  # ensure only encrypted files are uploaded
  if file "$INPUT" | grep -qv "PGP symmetric key encrypted data"; then
    echo "WARNING, ATTEMPTED TO UPLOAD AN UNENCRYPTED FILE, exiting..."
    exit 1
  fi
  local FILE_KEY=$(basename "$INPUT")

  printf "Uploading  $FILE_KEY..."
  if [ -n "$DRY_RUN_FOLDER" ]; then
    cp "$INPUT" "$DRY_RUN_FOLDER/$FILE_KEY"
  else
    aws s3 cp "$INPUT" "s3://$AWS_BUCKET_NAME/$FILE_KEY" \
      --storage-class "$STORAGE_CLASS" \
      --quiet
    # tag with password hint
    local TAG=$(jq -n -c --arg password "$SECRET_MASTER_KEY_HINT" '{ "TagSet": [{ "Key": "password", "Value": $password }] }')
    aws s3api put-object-tagging \
      --bucket "$AWS_BUCKET_NAME" \
      --key "$FILE_KEY" \
      --tagging "$TAG"
  fi
  echo " Done"
}

function createSnapshot() { # 1=CONFIG_PATH, 2=INDEX_SNAR, 3=SNAPSHOT_OUTPUT 
  local CONFIG_PATH="$1"
  local INDEX_SNAR="$2"
  local SNAPSHOT_OUTPUT="$3"

  ## Run injectors
  printf "Running injectors"
  source "$CONFIG_PATH/injectors.sh"
  for injector in $(declare -F | grep "declare -f inject_" | awk '{ print $3 }'); do
    printf "."
    $injector "$INJECT_FOLDER"
    if [ $? -ne 0 ]; then
      echo "Injector: \"$injector\" failed, exiting"
      exit 1
    fi
  done
  echo " Done"

  mkdir "$INJECT_FOLDER/config"
  cp "$CONFIG_PATH"/exclude*.list "$CONFIG_PATH"/include*.list "$INJECT_FOLDER/config/"

  MASTER_EXCLUDE_FILE="$TMP_FOLDER/master-exclude.list"
  populateMasterExcludeFile "$MASTER_EXCLUDE_FILE" "$CONFIG_PATH"

  MASTER_INCLUDE_FILE="$TMP_FOLDER/master-include.list"
  populateMasterIncludeFile "$MASTER_INCLUDE_FILE" "$CONFIG_PATH"
  printf "\n${INJECT_FOLDER}" >> $MASTER_INCLUDE_FILE

  local transform="--transform=s|^$INJECT_FOLDER|/inject|"

  printf "Creating tarball..."
  tar \
    --use-compress-program "zstd -9 -T0" \
    --acls --xattrs \
    --absolute-names \
    --create --file="$SNAPSHOT_OUTPUT" \
    --listed-incremental="$INDEX_SNAR" \
    --wildcards-match-slash --exclude-from="$MASTER_EXCLUDE_FILE" \
    --transform="s|^$INJECT_FOLDER|/inject|" \
    --files-from="$MASTER_INCLUDE_FILE" 
  echo " Done"
  rm -r "$INJECT_FOLDER"
}

check_root
check_packages

check_initialised "$CONFIG_PATH"

# temp folder
TMP_FOLDER="$(mktemp -d)"
INJECT_FOLDER="/tar-aws-snapshot-$(uuidgen)" # at root so it cant be excluded
mkdir "$INJECT_FOLDER"
function cleanup {
  rm -r "$TMP_FOLDER"
  rm -rf "$INJECT_FOLDER" # incase of error ensure inject folder is deleted
}
trap cleanup EXIT

. $CONFIG_PATH/secrets.config # load secrets file

# AWS CREDENTIALS
export AWS_ACCESS_KEY_ID
export AWS_SECRET_ACCESS_KEY
export AWS_DEFAULT_REGION

BUCKET_FILE_LIST=$(getBucketFileList)
BUCKET_FILE_LIST_SNAPSHOT_ONLY=$(getBucketFileListSnapshotOnly "$BUCKET_FILE_LIST")


displayBucketInfo

INDEX_SNAR="$TMP_FOLDER/index.snar"
downloadIndexSnar "$INDEX_SNAR"

SNAPSHOT_NAME="$(getSnapshotName)"
SNAPSHOT_OUTPUT="$TMP_FOLDER/$SNAPSHOT_NAME.tar.zst"

createSnapshot "$CONFIG_PATH" "$INDEX_SNAR" "$SNAPSHOT_OUTPUT"

reviewSnapshot "$SNAPSHOT_OUTPUT"

# update index.snar, not stored as deep_archive as its downloaded on every upload
COMPRESSED_INDEX_SNAR="$TMP_FOLDER/index.snar.zst"
zstd -9 -T0 --quiet "$INDEX_SNAR" "$COMPRESSED_INDEX_SNAR"
rm "$INDEX_SNAR"
# encrypt index.snar
ENCRYPTED_INDEX_SNAR="$TMP_FOLDER/index.snar.zst.gpg"
encryptFile "$COMPRESSED_INDEX_SNAR" "$ENCRYPTED_INDEX_SNAR"
uploadFile "$ENCRYPTED_INDEX_SNAR" "STANDARD"
# create backup of index.snar linked to created tarball
ARCHIVE_INDEX_SNAR="$TMP_FOLDER/$SNAPSHOT_NAME.snar.zst.gpg"
cp "$ENCRYPTED_INDEX_SNAR" "$ARCHIVE_INDEX_SNAR"
uploadFile "$ARCHIVE_INDEX_SNAR" "DEEP_ARCHIVE"

# upload snapshot tarball
ENCRYPTED_SNAPSHOT="$SNAPSHOT_OUTPUT.gpg"
encryptFile "$SNAPSHOT_OUTPUT" "$ENCRYPTED_SNAPSHOT"
uploadFile "$ENCRYPTED_SNAPSHOT" "DEEP_ARCHIVE"

