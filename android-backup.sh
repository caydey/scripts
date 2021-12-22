#!/bin/sh

SAVE_PATH=$1
## no param assume current directory
if [[ -z $SAVE_PATH ]]; then
	SAVE_PATH="."
elif [[ ! -d $SAVE_PATH ]]; then
	echo "directory not found"
	exit 1
fi


## exclude file
EXCLUDE_FILE="$SAVE_PATH/exclude.list"
if [[ ! -f $EXCLUDE_FILE ]]; then
	# create template exclude file
	echo -e "/data/data/*/cache/*\n\\n/sdcard/Download/*\n\n/mnt/media_rw/*/Movies/*" > $EXCLUDE_FILE

	echo "$EXCLUDE_FILE not found."
	echo "Creating '$EXCLUDE_FILE' with a default exclude template,"
	echo "Please review/modify it and run this script again"

	exit
fi


## initialize adb
echo "Waiting for device"
adb wait-for-device

adb root
if [[ $? -ne 0 ]]; then
	echo "adb root error, exiting"
	exit 1
fi


function create_archive() {
	DIRECTORY=$1

	DIRNAME=$(dirname $DIRECTORY)
	BASENAME=$(basename $DIRECTORY)  # /mnt/media_rw -> media_rw
	OUTPUT=$SAVE_PATH/$BASENAME.tar.zst

	## create exclude paramaters
	EXCLUDES=""
	for line in $(cat $EXCLUDE_FILE); do
		if [[ $line =~ ^$DIRECTORY.*$ ]]; then
			if [[ "$DIRNAME" == "/" ]]; then	## dirname of /my/path is /my but dirname of /path is /
				EXCLUDE="${line:${#DIRNAME}}"
			else
				EXCLUDE="${line:${#DIRNAME}+1}"
			fi
			EXCLUDES="$EXCLUDES --exclude='$EXCLUDE'"
		fi
	done

	if [[ -f $OUTPUT ]]; then
		mv $OUTPUT $OUTPUT.bak
	fi


	## restore old archive if Ctrl-c
	trap "rm $OUTPUT; [[ -f $OUTPUT.bak ]] && mv $OUTPUT.bak $OUTPUT; exit" SIGINT

	TABS="										"
	# send uncompressed tar over adb
	adb shell "tar $EXCLUDES -chf - -C $DIRNAME $BASENAME 2> /dev/null" | # PIPE
	# log adb transfer speed
	pv -F "$(basename $OUTPUT) - %t  Processed %b %r" | # PIPE
	# compress tar (on local machine)
	zstd -T0 | # PIPE
	# log archive size
	pv -F "${TABS}Archive Size %b" > $OUTPUT


	if [[ $? -eq 0 ]]; then # success
		if [[ -f $OUTPUT.bak ]]; then
			rm $OUTPUT.bak
		fi
	else # failure, delete archive and restore old one if it exists
		rm $OUTPUT
		if [[ -f $OUTPUT.bak ]]; then
			mv $OUTPUT.bak $OUTPUT
		fi
	fi
}

# start the backup
ANDROID_PATHS="/sdcard /data/data /mnt/media_rw"
for ANDROID_PATH in $ANDROID_PATHS; do
	create_archive $ANDROID_PATH
done
