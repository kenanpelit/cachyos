#!/usr/bin/env bash
# ==============================================================================
# Script: spotify-media.sh
# Description: Drive Spotify play/pause/next/prev whether it is the native
#              Spotify app (MPRIS bus "spotify") OR the web player running in a
#              Chromium browser (start-brave-spotify → MPRIS "brave.instanceN",
#              which mshellctl matches with the "browser" fragment).
#
#   `mshellctl media toggle spotify` only matches the native app; the web player
#   identifies itself as the browser ("Brave Origin"), so the spotify fragment
#   misses it. This wrapper picks the right fragment automatically.
#
# Usage: spotify-media [toggle|next|prev|status]   (default: toggle)
# ==============================================================================

set -uo pipefail

action="${1:-toggle}"

# Native Spotify app exposes MPRIS as org.mpris.MediaPlayer2.spotify(.instanceN).
if command -v playerctl >/dev/null 2>&1 \
   && playerctl -l 2>/dev/null | grep -qiE '^spotify(\.|$)'; then
  exec mshellctl media "$action" spotify
fi

# Otherwise drive the browser player (the Spotify web app lives there).
exec mshellctl media "$action" browser
