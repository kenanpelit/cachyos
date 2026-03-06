#!/usr/bin/env bash
# ==============================================================================
# Script: lofi.sh
# Description: YouTube lo-fi radio stream launcher using mpv and yt-dlp.
# Usage: lofi.sh
# ==============================================================================

if (ps aux | grep mpv | grep -v grep > /dev/null); then
    pkill mpv
else
    runbg mpv --no-video https://www.youtube.com/live/jfKfPfyJRdk?si=OF0HKrYFFj33BzMo
fi
