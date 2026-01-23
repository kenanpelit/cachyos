#!/usr/bin/env bash
# Opens imv starting at the given file, but including all images in that directory
if [ -f "$1" ]; then
    imv -n "$(basename "$1")" "$(dirname "$1")"
else
    imv "$@"
fi
