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

function snapshotList() { # SAVE_PATH
	SAVE_PATH=$1
	totalSizeBytes=0
	# header
	echo "   # │ Date                     │    Size │  Actual"
	echo "─────┼──────────────────────────┼─────────┼────────"
	i=0
	for SNAP_LOG in $(ls "$SAVE_PATH"/snapshots/??????-??????/rsync.log); do
		D=$(basename $(dirname "$SNAP_LOG")) # DATE
		# YYMMDD-hhmmss -> YYMMDD-hh:mm:ss
		PARSED="20${D:0:6} ${D:7:2}:${D:9:2}:${D:11:2}"
		FORMATTED=$(date -d"$PARSED" +"%a %d %b %Y %T")

		LOG_TAIL=$(tail -n 2 "$SNAP_LOG")
		SIZE=$(echo "$LOG_TAIL" | xargs | awk '{ print $18 }')
		ACTUAL_SIZE=$(echo "$LOG_TAIL" | xargs | awk '{ print $5 }')

		# <SNAPSHOT NUMBER> |
		printf "%4s │" "$i"
		# <DATE> |
		printf " $FORMATTED │"
		# <SIZE> |
		numfmt --zero-terminated --from=iec --to=iec --format="%8.1f │" "$SIZE"
		# <ACTUAL SIZE> |
		numfmt --zero-terminated --from=iec --to=iec --format="%8.1f" "$ACTUAL_SIZE"
		# newline
		echo
		((i++))

		# count total snapshots size
		snapshotSizeBytes=$(numfmt --from=iec "$ACTUAL_SIZE")
		totalSizeBytes=$(($totalSizeBytes + $snapshotSizeBytes))
	done

	totalSizeHuman=$(numfmt --to=iec --format=%.2f "$totalSizeBytes")
	echo "Total disk space used: $totalSizeHuman"
}

function snapshotCreate() { # SAVE_PATH, FORCE_ROOT
	SAVE_PATH=$1
	FORCE_ROOT=$2
	## check if root
	if [ "$FORCE_ROOT" = true ] && [ $UID -ne 0 ]; then
		echo "run as root or use the --no-root argument"
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
			echo "/dev/*" >$MASTER_EXCLUDE_FILE
			echo "/proc/*" >>$MASTER_EXCLUDE_FILE
			echo "/sys/*" >>$MASTER_EXCLUDE_FILE
			echo "/run/*" >>$MASTER_EXCLUDE_FILE
			echo "/tmp/*" >>$MASTER_EXCLUDE_FILE
			echo "/mnt/*" >>$MASTER_EXCLUDE_FILE
			echo "/lost+found" >>$MASTER_EXCLUDE_FILE
			echo "" >>$MASTER_EXCLUDE_FILE
			echo "/var/run/*" >>$MASTER_EXCLUDE_FILE
			echo "/var/lock/*" >>$MASTER_EXCLUDE_FILE
			echo "/var/tmp/*" >>$MASTER_EXCLUDE_FILE
			echo "" >>$MASTER_EXCLUDE_FILE
			echo "/home/*/.cache/*" >>$MASTER_EXCLUDE_FILE

			echo "Created '$MASTER_EXCLUDE_FILE' with a default exclude template,"
		fi
		if [[ ! -f "$MASTER_INCLUDE_FILE" ]]; then
			echo "/" >$MASTER_INCLUDE_FILE
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
	readarray -t SRC_FILES <$INCLUDE_FILE

	## rsync paramaters
	# if first snapshot dosent exist dont include --link-dest
	if [[ -d $SNAPSHOT_LAST ]]; then
		LINK_DEST="--link-dest=$(realpath $SNAPSHOT_LAST)/system/"
	fi

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
}

function snapshotHelp() {
	cat <<EOF
usage: $0 <command> [snapshot location] [--no-root]

  Create snapshot:
    $0 create [snapshot location] [--no-root]
        Creates snapshot, pass snapshot location as paramater or leave empty to
        default to current directory
        by default will require the user to be root, to bypass this pass the
				--no-root paramter at the end of the comand

  View snapshots:
    $0 list [snapshot location]
        View past snapshot details, includes size, date and total snapshot size
        footprint

  Command help:
    $0 help
        Show this menu

EOF
}

# parse args
SAVE_PATH=$2
FORCE_ROOT=true
if [[ "$2" == "--no-root" ]]; then
	unset SAVE_PATH
	FORCE_ROOT=false
elif [[ "$3" == "--no-root" ]]; then
	FORCE_ROOT=false
fi

## no param assume current directory
if [[ -z "$SAVE_PATH" ]]; then
	SAVE_PATH="."
elif [[ ! -d "$SAVE_PATH" ]]; then
	echo "directory not found '$SAVE_PATH'"
	exit 1
fi

case $1 in
"create" | "c")
	snapshotCreate "$SAVE_PATH" "$FORCE_ROOT"
	;;
"list" | "l")
	snapshotList "$SAVE_PATH"
	;;
"help" | "h" | *)
	snapshotHelp
	;;
esac
