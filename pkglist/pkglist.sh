#!/bin/sh

pacman -Qi |
awk '
	/^Name/{name=$3}  # name
	/^Version/{version=$3}  # version
	/^Installed Size/{size=$4; unit=$5}  # package size
	/^Validated By/{printf "%.1f%s %s %s\n", size,unit, name,version} # end of package details
' | # print package size,name,version
sort -h | # sort by size
awk '{
	#         size (BOLD-WHITE)    name (WHITE)       version (DIM-WHITE)
	printf "\033[1;29m%9s\033[0m \033[0;29m%s\033[0m\033[2;29m-%s\033[0m\n",
		$1, $2, $3
}' # add color, cant do it in the above awk as it messes up 'sort -h'
