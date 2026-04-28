#!/usr/bin/env bash
# ==============================================================================
# Script: mango-performance-mode
# Description: Switch MangoWM runtime visual/performance profiles.
# Usage: mango-performance-mode {normal|gaming|battery|status}
# ==============================================================================

set -euo pipefail

MODE="${1:-status}"

usage() {
  cat <<'EOF'
Usage: mango-performance-mode {normal|gaming|battery|status}

Profiles are applied through MangoWM's runtime setoption dispatcher.
EOF
}

require_mmsg() {
  command -v mmsg >/dev/null 2>&1 || {
    echo "mmsg is required" >&2
    exit 1
  }
}

set_option() {
  local key="$1"
  local value="$2"
  mmsg -d "setoption,${key},${value}" >/dev/null
}

apply_normal() {
  set_option blur 1
  set_option blur_layer 0
  set_option shadows 1
  set_option layer_shadows 0
  set_option animations 1
  set_option layer_animations 1
  set_option allow_tearing 2
  set_option idleinhibit_ignore_visible 0
  set_option cursor_hide_timeout 0
}

apply_gaming() {
  set_option blur 0
  set_option blur_layer 0
  set_option shadows 0
  set_option layer_shadows 0
  set_option animations 0
  set_option layer_animations 0
  set_option allow_tearing 1
  set_option idleinhibit_ignore_visible 1
  set_option cursor_hide_timeout 0
}

apply_battery() {
  set_option blur 0
  set_option blur_layer 0
  set_option shadows 0
  set_option layer_shadows 0
  set_option animations 1
  set_option layer_animations 0
  set_option allow_tearing 0
  set_option idleinhibit_ignore_visible 0
  set_option cursor_hide_timeout 2
}

require_mmsg

case "${MODE}" in
normal)
  apply_normal
  ;;
gaming)
  apply_gaming
  ;;
battery)
  apply_battery
  ;;
status)
  mmsg -g -b
  mmsg -g -l
  ;;
-h | --help | help)
  usage
  ;;
*)
  usage >&2
  exit 2
  ;;
esac
