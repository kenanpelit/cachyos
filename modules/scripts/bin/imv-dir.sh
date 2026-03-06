#!/usr/bin/env bash
# ==============================================================================
# Script: imv-dir.sh
# Description: Opens imv at a file while including all images in its directory.
# Usage: imv-dir.sh [file|dir]
# ==============================================================================
if [ -f "$1" ]; then
    imv -n "$(basename "$1")" "$(dirname "$1")"
else
    imv "$@"
fi
