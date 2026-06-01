#!/usr/bin/env bash
# ==============================================================================
# osc-media.sh — compatibility shim. Superseded by `mplay media` (margo's
# native media controller). Old `osc-media [PLAYER] COMMAND` / `osc-media
# COMMAND` invocations are mapped to `mplay media COMMAND [PLAYER]`. Prefer
# calling `mplay media …` directly in new config.
# ==============================================================================
set -euo pipefail

case "${1:-}" in
  spotify | vlc | mpv | mpd | mpc | browser)
    player="$1"
    [[ "$player" == "mpc" ]] && player="mpd"
    exec mplay media "${2:-toggle}" "$player"
    ;;
  "" | -h | --help | help)
    exec mplay media --help
    ;;
  *)
    exec mplay media "$1"
    ;;
esac
