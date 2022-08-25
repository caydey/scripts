# move_torrent

QBittorrent autorun script to move and rename torrents once they are downloaded
The script will create hardlinks instead of moving the files to allow for seeding

# Usage

- edit `MOVIES_FOLDER` and `MOVIES_FOLDER` variables in `move_torrent.py`
- set QBittorrent autorun script as `./<move_torrent.py location> "%F"`
