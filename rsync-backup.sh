#!/bin/sh

# my_backup/
# |- rsync_backup.sh        this script
# |- exclude.list           list of files to be excluded
# |- logs/                  rsync logs
# |  `- YYMMDD-hhmmss.log   output from rsync
# `- system/                copy of the root system


# check if running as root
if [ $UID -ne 0 ]; then
	echo "run as root"
	exit 1
fi

## save path
SAVE_PATH=$1
## no param assume current directory
if [[ -z $SAVE_PATH ]]; then
	SAVE_PATH="."
elif [[ ! -d $SAVE_PATH ]]; then
	echo "directory not found"
	exit 1
fi


# exclude file
EXCLUDE_FILE=$SAVE_PATH/exclude.list
## exclude.list not found, probably first time running script
if [[ ! -f $EXCLUDE_FILE ]]; then
	# create template exclude file
	echo "/dev/*
/proc/*
/sys/*
/run/*
/tmp/*
/mnt/*
/lost+found

/var/run/*
/var/lock/*
/var/tmp/*

/home/*/.cache/*" > $EXCLUDE_FILE

	echo "Creating '$EXCLUDE_FILE' with a default exclude template,"
	echo "Please review/modify it and run script again"
	exit
fi

# location to copy filesystem to
BACKUP_PATH=$SAVE_PATH/system
# create BACKUP_PATH directory if it dosent exist
[[ -d $BACKUP_PATH ]] || mkdir $BACKUP_PATH

# log folder
# create BACKUP_PATH directory if it dosent exist
LOG_PATH=$SAVE_PATH/logs
[[ -d $LOG_PATH ]] || mkdir $LOG_PATH
LOG_FILE=$LOG_PATH/$(date +'%y%m%d-%H%M%S').log

## rsync paramaters
OPT="-aAXH -vh" # archive, ACLs, xattrs, hard links, verbose, human sizes
SRC="/"
EXCLUDE="--exclude-from=$EXCLUDE_FILE"
DELETE="--delete --delete-excluded"
LOG="--log-file=$LOG_FILE"

echo "Started backup"

## rsync command
rsync $OPT $DELETE $EXCLUDE $LOG $SRC $BACKUP_PATH

echo "syncing drive..."
sync $BACKUP_PATH

echo "Successfully created backup."
