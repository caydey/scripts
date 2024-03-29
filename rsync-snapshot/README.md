# rsync-snapshot

required sudo to run by default, disable with the `--no-root` paramater if you are creating snapshots of non-root files

## Usage

- copy rsync-snapshot.sh to a folder that you want your snapshots to be saved in
- cd into the folder and run `./rsync-snapshot.sh create --no-root` to init files
- a folder named `snapshots` will be created along with `exclude.list` and `include.list` files
- edit `exclude.list` and `include.list` respectivly with the files you want include/exclude in the snapshot
- finally run `./rsync-snapshot.sh create` to take your first snapshot
- you can also run `./rsync-snapshot.sh help` afterwards to show other snapshot options

## Generated folder structure

```
.                                   # your folder to store the snapshots in
├── rsync_snapshot.sh               # this script
├── exclude.list                    # list of files to be excluded
├── include.list                    # list of files to be included
└── snapshots/                      # folder generated by script to store snapshots
    ├── YYMMDD-hhmmss/              # snapshot folder
    │   ├── system/                 # snapshot of the root system
    │   ├── exclude.list            # excluded files for this snapshot
    │   ├── rsync.log               # rsync log for this snapshot
    │   └── script.sh               # script used for this snapshot
    └── last -> YYMMDD-hhmmss/      # links to last snapshot
```
