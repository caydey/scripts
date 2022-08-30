# integrity.sh

## Usage

`integrity.sh <command> [directory]` If [directory] option not specified script will default to your current directory '.'

### Commands

`integrity.sh generate [directory]`
Create a '.integrity' file which contains all files in a directory with their respective hashes

`integrity.sh check [directory]`
compares '.integrity' file with all files in directory and lists any changes

`integrity.sh append [directory]`
Updates '.integrity' file with new and deleted files. Assumes all hashes are correct and will not detect modified files
