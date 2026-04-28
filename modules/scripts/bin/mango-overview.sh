#!/usr/bin/env bash
# ==============================================================================
# Script: mango-overview
# Description: Open, close, or toggle MangoWM overview using live IPC state.
# Usage: mango-overview {open|close|toggle|status}
# ==============================================================================

set -euo pipefail

ACTION="${1:-toggle}"
TAG_MASK_ALL="${MANGO_OVERVIEW_TAG_MASK:-511}"

usage() {
  cat <<'EOF'
Usage: mango-overview {open|close|toggle|status}

Uses mmsg state to avoid accidental open/close inversion for gesture bindings.
EOF
}

selected_monitor() {
  mmsg -g -o 2>/dev/null | awk '$2 == "selmon" && $3 == "1" { print $1; exit }'
}

active_mask_for_monitor() {
  local monitor="$1"
  mmsg -g -t 2>/dev/null | awk -v monitor="$monitor" '$1 == monitor && $2 == "tags" && $3 ~ /^[0-9]+$/ { print $4; exit }'
}

is_open() {
  local monitor mask
  monitor="$(selected_monitor)"
  [[ -n "$monitor" ]] || return 1
  mask="$(active_mask_for_monitor "$monitor")"
  [[ "$mask" == "$TAG_MASK_ALL" ]]
}

toggle_overview() {
  mmsg -d toggleoverview >/dev/null
}

command -v mmsg >/dev/null 2>&1 || {
  echo "mmsg is required" >&2
  exit 1
}

case "$ACTION" in
open)
  if ! is_open; then
    toggle_overview
  fi
  ;;
close)
  if is_open; then
    toggle_overview
  fi
  ;;
toggle)
  toggle_overview
  ;;
status)
  if is_open; then
    echo "open"
  else
    echo "closed"
  fi
  ;;
-h | --help | help)
  usage
  ;;
*)
  usage >&2
  exit 2
  ;;
esac
