#!/usr/bin/env bash
# ==============================================================================
# margo-mpv.sh — compatibility shim. Superseded by the first-party `mplay`
# binary (margo's m* tool family). Old verbs are mapped to the new
# subcommands so existing keybinds keep working; prefer calling `mplay`
# directly in new config.
# ==============================================================================
set -euo pipefail

cmd="${1:-}"
[[ $# -gt 0 ]] && shift

case "$cmd" in
  playback)   exec mplay toggle "$@" ;;
  play-yt)    exec mplay play "$@" ;;
  save-yt)    exec mplay download "$@" ;;
  move)       exec mplay snap "$@" ;;
  stick)      exec mplay pin "$@" ;;
  top)        exec mplay focus "$@" ;;
  wallpaper)  exec mplay wallpaper start "$@" ;;
  ""|-h|--help|help) exec mplay --help ;;
  *)          exec mplay "$cmd" "$@" ;;  # start/toggle/play/snap/pin/focus/stop pass through
esac
