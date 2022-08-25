#!/usr/bin/env python3
import sys
import os
import re
import shutil

import requests

MOVIES_FOLDER = '/data/movies/'
SHOWS_FOLDER = '/data/shows/'
MEDIA_FILETYPES = ('mp4', 'mkv', 'MP4', 'MKV')

# works best with qbittorrent Autorun script '<script location> "%F"'


DRY = False
# DRY=True

TEST_MODE = False
# TEST_MODE = True


def main():
    if TEST_MODE:
        test_mode()
    else:
        torrent_path = fetch_params()

        torrent_type = get_torrent_type(torrent_path)

        error = None
        if torrent_type == 'MOVIE':
            error = handle_movie(torrent_path)
        elif torrent_type == 'SHOW':
            error = handle_show(torrent_path)
        else:
            error = "torrent not recgonized"
        if error:
            print(error)
            sys.exit(1)


def test_mode():
    print("---Testing Movies---")
    test_movies()

    print("---Testing Shows---")
    test_shows()


def test_movies():
    titles = (
        ('The.Human.Centipede.III.Final.Sequence.2015.1080p.BluRay.x264.YIFY.mp4',
         'The Human Centipede III Final Sequence (2015).mp4'),
        ('The.Human.Centipede.II.Full.Sequence.2011.UNRATED.DC.1080p.BluRay.H264.AAC-RARBG.mp4',
         'The Human Centipede II Full Sequence (2011).mp4'),
        ('The.Batman.2022.1080p.WEBRip.x264.AAC5.1-[YTS.MX].mp4',
         'The Batman (2022).mp4'),
        ('X.2022.1080p.WEBRip.x264.AAC5.1-[YTS.MX].mp4',
         'X (2022).mp4'),
        ('Wyrmwood.Road.of.the.Dead.2014.1080p.BluRay.x264.YIFY.mp4',
         'Wyrmwood Road of the Dead (2014).mp4'),
        ('Wyrmwood.Apocalypse.2021.1080p.WEBRip.x264.AAC5.1-[YTS.MX].mp4',
         'Wyrmwood Apocalypse (2021).mp4'),
        ('The.Outfit.2022.1080p.BluRay.x264.AAC5.1-[YTS.MX].mp4',
         'The Outfit (2022).mp4'),
        ('2012.2009.1080p.BluRay.x265-RARBG.mp4',
         '2012 (2009).mp4'),
        ('300 (2006) [1080p] [BluRay] [YTS.MX].mp4',
         '300 (2006).mp4'),
        ('Dude.Wheres.My.Car.2000.1080p.BluRay.x264.AAC5.1-[YTS.MX].mp4',
         'Dude Wheres My Car (2000).mp4'),
        ('Snatch.2000.1080p.BluRay.x264-[YTS.AM].mp4',
         'Snatch (2000).mp4'),
        ('Snatch.2000.REPACK.2160p.4K.BluRay.x265.10bit.AAC5.1-[YTS.MX].mkv',
         'Snatch (2000).mkv')
    )
    for (title, expected) in titles:
        converted = convert_movie_title(title)
        if (converted == expected):
            print("\033[1;32mPASSED\033[0m", converted)
        else:
            print("\033[1;31mFAILED\033[0m", converted)


def test_shows():
    titles = (
        ('family.guy.s20e20.1080p.web.h264-cakes[eztv.re].mkv',
         ('Family Guy S20E20 - Jersey Bore.mkv', 'Family Guy')),
        ('Stranger.Things.S04E01.1080p.HEVC.x265-MeGusta[eztv.re].mkv',
         ('Stranger Things S04E01 - Chapter One: The Hellfire Club.mkv', 'Stranger Things')),
        ('Brooklyn.Nine-Nine.S05E19.WEB.x264-TBS[eztv].mp4',
         ('Brooklyn Nine-Nine S05E19 - Bachelor-ette Party.mp4', 'Brooklyn Nine-Nine'))
    )
    for (title, expected) in titles:
        converted = convert_show_title(title)
        if (converted == expected):
            print("\033[1;32mPASSED\033[0m", converted[0])
        else:
            print("\033[1;31mFAILED\033[0m", converted[0])


def handle_show(torrent_path):
    # types
    # single file
    # folder with single file
    # folder with season

    if os.path.isfile(torrent_path):  # single file torrent
        new_filename, show_name = convert_show_title(
            os.path.basename(torrent_path))
        show_folder = get_show_destination_folder(show_name)
        moved_location = os.path.join(show_folder, new_filename)
        move_file(torrent_path, moved_location)
    else:  # folder with many shows inside it
        for (root, dirs, files) in os.walk(torrent_path):
            for f in files:
                if get_torrent_type(f) == 'SHOW':
                    handle_show(os.path.join(root, f))


def get_show_destination_folder(show_name):
    show_destination_folder = os.path.join(SHOWS_FOLDER, show_name)
    if not os.path.exists(show_destination_folder):
        if DRY:
            print("mkdir '"+show_destination_folder+"'")
        else:
            os.mkdir(show_destination_folder)
    return show_destination_folder


def convert_show_title(torrent_show_file):
    result = re.search(r'(.+).[Ss](\d\d)[Ee](\d\d)', torrent_show_file)
    groups = result.groups()
    if len(groups) != 3:
        print("regex fail")
        sys.exit(1)

    show_name = groups[0]
    show_name = show_name.replace('.', ' ').strip()  # the.show => the show
    # The Boys 2019 => The Boys
    if show_name[-4:].isnumeric():
        show_name = show_name[:-5]
    # The Boys - S02E01 - The Big Ride.mkv
    if show_name[-2:] == ' -':
        show_name = show_name[:-2]

    show_season = groups[1]
    show_episode = groups[2]
    show_season_episode = f'S{show_season.zfill(2)}E{show_episode.zfill(2)}'
    extension = os.path.splitext(torrent_show_file)[1]

    response = requests.get(
        'https://api.tvmaze.com/singlesearch/shows',
        params={
            'q': show_name,
        }
    )
    if not response:
        print("api error")
        sys.exit(1)
    api_json = response.json()

    # properly formatted show name 'family guy' => 'Family Guy'
    show_name = api_json['name']
    api_show_id = api_json['id']  # used in next api call to get episode name

    response = requests.get(
        f'https://api.tvmaze.com/shows/{api_show_id}/episodebynumber',
        params={
            'season': show_season,
            'number': show_episode
        }
    )
    if not response:
        print('api_error')
        sys.exit(1)

    api_json = response.json()
    episode_name = api_json['name']
    episode_name = episode_name.replace('/', '-')  # illegal filename chars

    new_filename = f'{show_name} {show_season_episode} - {episode_name}{extension}'
    return new_filename, show_name


def handle_movie(torrent_path):
    torrent_movie_path = get_movie_file(torrent_path)
    if not torrent_movie_path:
        return 'movie not found in torrent folder'

    movie_title = convert_movie_title(os.path.basename(torrent_movie_path))
    moved_location = os.path.join(MOVIES_FOLDER, movie_title)
    move_file(torrent_movie_path, moved_location)


def convert_movie_title(torrent_movie_file):
    RESOLUTIONS = ('720p', '1080p', '2160p')
    resolution_split = None
    for resolution in RESOLUTIONS:
        split = torrent_movie_file.split(resolution, 1)
        if len(split) == 2:
            resolution_split = split[0]
            break

    if not resolution_split:
        print("resolution split failed")
        sys.exit(1)

    result = re.search(r'(.+)(?:\s|.)+(\d\d\d\d)', resolution_split)
    groups = result.groups()
    if len(groups) != 2:
        print("regex fail")
        sys.exit(1)

    title = groups[0]
    title = title.replace('.', ' ').strip()
    year = groups[1]
    extension = os.path.splitext(torrent_movie_file)[1]

    converted_file = f'{title} ({year}){extension}'

    return converted_file


def get_movie_file(torrent_path):

    # single file torrent
    if os.path.isfile(torrent_path) and torrent_path.endswith(FILETYPES):
        return torrent_path

    # iterate over all files in torrent and find
    # the largest file with a mp4/mkv extension
    movie_file = None
    movie_size = 0
    for (root, dirs, files) in os.walk(torrent_path):
        for f in files:
            full_path = os.path.join(root, f)
            if (f.endswith(MEDIA_FILETYPES)):  # media filetype
                size = os.path.getsize(full_path)
                if size > movie_size:
                    movie_size = size
                    movie_file = full_path
    return movie_file


def get_torrent_type(torrent_path):
    filename = os.path.basename(torrent_path)
    if filename == "":
        filename = os.path.basename(torrent_path[:-1])
    # S??E?? somewhere in the title means show
    if re.search(r'.+[Ss]\d{1,2}[Ee]\d{1,2}.+', filename):
        return 'SHOW'
    # multiple movie files in directory means show
    media_files = 0
    for (root, dirs, files) in os.walk(torrent_path):
        for f in files:
            if f.endswith(MEDIA_FILETYPES):
                media_files += 1
    if media_files >= 3:
        return 'SHOW'

    # a year between 1900-2099 in the title means movie
    if re.search(r'.+(?:19|20)[0-9][0-9].+', filename):
        return 'MOVIE'

    return 'OTHER'


def move_file(src, dest):
    if DRY:
        print(f'ln "{src}" "{dest}"')
    else:
        if os.path.exists(dest):
            print(dest+" already exists, not moving")
        else:
            os.link(src, dest)


def fetch_params():
    if len(sys.argv) != 2:
        print("invalid args")
        sys.exit(1)
    torrent_path = sys.argv[1]
    if not os.path.exists(torrent_path):
        print("torrent not found")
        sys.exit(1)
    return torrent_path


if __name__ == '__main__':
    main()
