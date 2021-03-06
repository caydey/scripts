#!/bin/sh

# my_snapshots/                 your folder to store the snapshots in
# |- rsync_snapshot.sh          this script
# |- exclude.list               list of files to be excluded
# |- include.list               list of files to be included
# `- snapshots/                 folder generated by script to store snapshots
#    |- YYMMDD-hhmmss/          snapshot folder
#    |  |- system/              snapshot of the root system
#    |  |- exclude.list         excluded files for this snapshot
#    |  |- rsync.log            rsync log for this snapshot
#    |  `- script.sh            script used for this snapshot
#    `- last -> YYMMDD-hhmmss/  links to last snapshot

# parse args
SAVE_PATH=$1
FORCE_ROOT=true
if [[ "$1" == "--no-root" ]]; then
	SAVE_PATH="."
	FORCE_ROOT=false
elif [[ "$2" == "--no-root" ]]; then
	FORCE_ROOT=false
fi

## check if root
if [ "$FORCE_ROOT" = true ] && [ $UID -ne 0 ]; then
	echo "run as root"
	exit 1
fi

## no param assume current directory
if [[ -z "$SAVE_PATH" ]]; then
	SAVE_PATH="."
elif [[ ! -d "$SAVE_PATH" ]]; then
	echo "directory not found '$SAVE_PATH'"
	exit 1
fi

# snapshot_s_ path
SNAPSHOTS_FOLDER=$SAVE_PATH/snapshots
if [[ ! -d $SNAPSHOTS_FOLDER ]]; then
	echo "Creating $SNAPSHOTS_FOLDER"
	mkdir "$SNAPSHOTS_FOLDER"
fi

# exclude file
MASTER_EXCLUDE_FILE="$SAVE_PATH/exclude.list"
MASTER_INCLUDE_FILE="$SAVE_PATH/include.list"
## exclude.list or include.list not found, probably first time running script
if [[ ! -f "$MASTER_EXCLUDE_FILE" ]] || [[ ! -f "$MASTER_INCLUDE_FILE" ]]; then
	if [[ ! -f "$MASTER_EXCLUDE_FILE" ]]; then
		# create template exclude file
		echo "/dev/*"			> $MASTER_EXCLUDE_FILE
		echo "/proc/*"			>> $MASTER_EXCLUDE_FILE
		echo "/sys/*"			>> $MASTER_EXCLUDE_FILE
		echo "/run/*"			>> $MASTER_EXCLUDE_FILE
		echo "/tmp/*"			>> $MASTER_EXCLUDE_FILE
		echo "/mnt/*"			>> $MASTER_EXCLUDE_FILE
		echo "/lost+found"		>> $MASTER_EXCLUDE_FILE
		echo ""					>> $MASTER_EXCLUDE_FILE
		echo "/var/run/*"		>> $MASTER_EXCLUDE_FILE
		echo "/var/lock/*"		>> $MASTER_EXCLUDE_FILE
		echo "/var/tmp/*"		>> $MASTER_EXCLUDE_FILE
		echo ""					>> $MASTER_EXCLUDE_FILE
		echo "/home/*/.cache/*" >> $MASTER_EXCLUDE_FILE

		echo "Created '$MASTER_EXCLUDE_FILE' with a default exclude template,"
	fi
	if [[ ! -f "$MASTER_INCLUDE_FILE" ]]; then
		echo "/" > $MASTER_INCLUDE_FILE
		echo "Created '$MASTER_INCLUDE_FILE' with a default include template,"
	fi
	echo "Please review/modify them and run script again"
	exit
fi

# snapshot path
SNAPSHOT_PATH=$SNAPSHOTS_FOLDER/$(date +'%y%m%d-%H%M%S')
mkdir "$SNAPSHOT_PATH"

# last snapshot
SNAPSHOT_LAST=$SNAPSHOTS_FOLDER/last

# snapshot backup location
SNAPSHOT_LOCATION=$SNAPSHOT_PATH/system
mkdir "$SNAPSHOT_LOCATION"

# snapshot log
SNAPSHOT_LOG=$SNAPSHOT_PATH/rsync.log

# copy exclude and include files to snapshot folder as it may change over time
EXCLUDE_FILE=$SNAPSHOT_PATH/exclude.list
cp "$MASTER_EXCLUDE_FILE" "$EXCLUDE_FILE"
INCLUDE_FILE=$SNAPSHOT_PATH/include.list
cp "$MASTER_INCLUDE_FILE" "$INCLUDE_FILE"

# copy this script to snapshot folder as it may also change in future
SCRIPT_FILE=$SNAPSHOT_PATH/script.sh
cp "$0" "$SCRIPT_FILE"

## delete partial snapshots on ctrl-c
function interruptHandler() {
	echo "Operation canceled, deleting partial snapshot..."
	rm -rf "$SNAPSHOT_PATH"
	echo "Partial snapshot deleted, exiting."
	exit
}
trap interruptHandler SIGINT


# rsync will autoescape any bash variables passed as params so passing a space
# seperated string of srcs wont work as it will be read as a single filename
# a workaround is to store the src directories in an array and use the [*]
# array operator to pass the files to rsync
IFS='' # split on newlines not whitespaces
readarray -t SRC_FILES < $INCLUDE_FILE

## rsync paramaters
# if first snapshot dosent exist dont include --link-dest
[[ -d $SNAPSHOT_LAST ]] && LINK_DEST="--link-dest=$(realpath $SNAPSHOT_LAST)/system/"

echo "Started creating snapshot"

## rsync command
rsync \
	-aHAX -vh \
	$LINK_DEST \
	--exclude-from=$EXCLUDE_FILE \
	--log-file=$SNAPSHOT_LOG \
	--relative \
	${SRC_FILES[*]} \
	$SNAPSHOT_LOCATION

echo "Successfully created snapshot."


# update latest snapshot pointer
rm -f $SNAPSHOT_LAST
ln -s $(basename $SNAPSHOT_PATH) $SNAPSHOT_LAST

echo "syncing drive..."
sync $SNAPSHOT_LOCATION

