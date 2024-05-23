#!/bin/sh

## save path
SAVE_PATH=$2
## no param assume current directory
if [[ -z $SAVE_PATH ]]; then
  SAVE_PATH="."
elif [[ ! -d $SAVE_PATH ]]; then
  echo "directory not found"
  exit 1
fi

# use newlines instead of spaces as seperators when looping through strings
IFS=$'\n'
set -f

HASH_CMD=sha256sum
INTEGRITY_FILE=./.integrity
cd $SAVE_PATH

function generate() {
  # clear integrity file
  cat /dev/null >$INTEGRITY_FILE

  # display info about directory
  fileCount=$(find . -type f -not -wholename "$INTEGRITY_FILE" | wc -l)
  totalSize=$(du -sh . | awk '{print $1}')
  echo "generating hashes for $fileCount files ($totalSize)"

  function make_hash() {
    printf '.' # "loading" bar
    $HASH_CMD "$1" >>$INTEGRITY_FILE
  }
  for file in $(find . -type f -not -wholename "$INTEGRITY_FILE" -printf '%P\n'); do
    # threaded
    make_hash "$file" &
  done

  wait # wait for threads to finish

  # sort integrity file entries by path
  sort -k 2 -o $INTEGRITY_FILE $INTEGRITY_FILE

  echo # newline for "loading" bar
  echo "created integrity file"
}

function append() {
  # ./integrity.sh generate has been run on directory
  if [ ! -f "$INTEGRITY_FILE" ]; then
    echo "'$INTEGRITY_FILE' file not found"
    exit 1
  fi

  # check for deleted files
  for line in $(cat $INTEGRITY_FILE); do
    path=$(echo "$line" | grep -Po '(?<=  ).*')
    if [ ! -f "$path" ]; then # path dosent exist
      # escape path for regex use
      line_esc="$(echo "$line" | sed 's/[^-A-Za-z0-9_]/\\&/g')"
      sed -i "/$line_esc/d" $INTEGRITY_FILE
      printf "\033[1;31mremoved\033[0m %s\n" "$path" # <RED>removed</RED> $path
    fi
  done

  function make_hash() {
    $HASH_CMD "$1" >>$INTEGRITY_FILE
    printf "\033[1;32madded\033[0m %s\n" "$1" # <GREEN>added</GREEN> $path
  }

  # check for new files
  for path in $(find . -type f -not -wholename "$INTEGRITY_FILE" -printf '%P\n'); do
    # path_esc="$(echo "$path" | sed 's/[^-A-Za-z0-9_]/\\&/g')"
    if ! grep -q -F "$path" $INTEGRITY_FILE; then
      # threaded
      make_hash "$path" &
    fi
  done

  wait # wait for threads to finish

  # re-sort integrity file entries by path
  sort -k 2 -o $INTEGRITY_FILE $INTEGRITY_FILE
}

function check() {
  # ./integrity.sh generate has been run on directory
  if [ ! -f "$INTEGRITY_FILE" ]; then
    echo "'$INTEGRITY_FILE' file not found"
    exit 1
  fi

  good=0
  modified=0
  deleted=0
  new=0

  # check for deleted files
  for line in $(cat $INTEGRITY_FILE); do
    path=$(echo "$line" | grep -Po '(?<=  ).*')
    if [ ! -f "$path" ]; then # path dosent exist
      ## <BLUE>deleted</BLUE> $path
      printf "\033[1;34mdeleted\033[0m %s\n" "$path"
      deleted=$(($deleted + 1))
    fi
  done

  # check for new and modified files
  for path in $(find . -type f -not -wholename "$INTEGRITY_FILE" -printf '%P\n'); do
    path_esc="$(echo "$path" | sed 's/[^-A-Za-z0-9_]/\\&/g')" # escape path for regex use
    hash=$(cat $INTEGRITY_FILE | grep -Po "[0-9a-f]+(?=  $path_esc$)")
    if [[ -z "$hash" ]]; then # file hash not found in integrity file, new file
      # <YELLOW>new</YELLOW> $path
      printf "\033[1;33mnew\033[0m %s\n" "$path"
      new=$(($new + 1))
    else
      # check hash
      actualpathhash=$($HASH_CMD "$path" | xargs -0 | awk '{print $1}')
      if [[ "$hash" == "$actualpathhash" ]]; then # hashes match
        # <GREEN>good</GREEN> $path
        printf "\033[1;32mgood\033[0m %s\n" "$path"
        good=$(($good + 1))
      else # hashes do not match
        # <RED>modified</RED> $path
        printf "\033[1;31mmodified\033[0m %s\n" "$path"
        modified=$(($modified + 1))
      fi
    fi
  done

  printf "checked %d files\n" $(($good + $modified + $deleted + $new))
  printf "\033[1;32mgood: %-6d\033[0m" $good         # <GREEN>good</GREEN> $good
  printf "\033[1;31mmodified: %-6d\033[0m" $modified # <RED>modified</RED> $modified
  printf "\033[1;34mdeleted: %-6d\033[0m" $deleted   # <BLUE>deleted</BLUE> $deleted
  printf "\033[1;33mnew: %-6d\033[0m" $new           # <YELLOW>new</YELLOW> $new
  echo
}

function help() {
  cat <<EOL
usage: $0 <command> [directory]

  If [directory] option not specified script will default to your current
  directory '.'
  
  Create integrity file:
    $0 generate [directory]
        Create a '.integrity' file which contains all files in a directory with
        their respective hashes
  Check integrity of directory:
    $0 check [directory]
        compares '.integrity' file with all files in directory and lists any
        changes
  Append new files
    $0 append [directory]
        Updates '.integrity' file with new and deleted files. Assumes all hashes
        are correct and will not detect modified files

EOL
}

case $1 in
"generate" | "g")
  generate
  ;;
"check" | "c")
  check
  ;;
"append" | "a" | "update" | "u")
  append
  ;;
*)
  help
  ;;
esac
