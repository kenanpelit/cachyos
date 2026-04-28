#!/usr/bin/env bash
# ==============================================================================
# Script: mango-virtual-output
# Description: Manage MangoWM headless outputs for remote desktop/screen share.
# Usage: mango-virtual-output {start|stop|status}
# ==============================================================================

set -euo pipefail

ACTION="${1:-status}"
OUTPUT_NAME="${MANGO_VIRTUAL_OUTPUT_NAME:-HEADLESS-1}"
MODE="${MANGO_VIRTUAL_OUTPUT_MODE:-1920x1080@60Hz}"
POSITION="${MANGO_VIRTUAL_OUTPUT_POSITION:-1920,0}"
SCALE="${MANGO_VIRTUAL_OUTPUT_SCALE:-1}"

usage() {
  cat <<EOF
Usage: mango-virtual-output {start|stop|status}

Environment:
  MANGO_VIRTUAL_OUTPUT_NAME      default: $OUTPUT_NAME
  MANGO_VIRTUAL_OUTPUT_MODE      default: $MODE
  MANGO_VIRTUAL_OUTPUT_POSITION  default: $POSITION
  MANGO_VIRTUAL_OUTPUT_SCALE     default: $SCALE
EOF
}

require_mango_ipc() {
  command -v mmsg >/dev/null 2>&1 || {
    echo "mmsg is required" >&2
    exit 1
  }
}

output_exists() {
  command -v wlr-randr >/dev/null 2>&1 || return 1
  wlr-randr 2>/dev/null | awk '{ print $1 }' | grep -Fxq "$OUTPUT_NAME"
}

start_output() {
  require_mango_ipc
  if ! output_exists; then
    mmsg -d create_virtual_output >/dev/null
    sleep 0.35
  fi

  if command -v wlr-randr >/dev/null 2>&1 && output_exists; then
    wlr-randr \
      --output "$OUTPUT_NAME" \
      --on \
      --custom-mode "$MODE" \
      --pos "$POSITION" \
      --scale "$SCALE"
  fi
}

stop_output() {
  require_mango_ipc
  mmsg -d destroy_all_virtual_output >/dev/null
}

status_output() {
  if output_exists; then
    wlr-randr | awk -v output="$OUTPUT_NAME" '
      $1 == output { printing = 1 }
      printing { print }
      printing && NF == 0 { printing = 0 }
    '
  else
    echo "$OUTPUT_NAME is not present"
  fi
}

case "$ACTION" in
start)
  start_output
  ;;
stop)
  stop_output
  ;;
status)
  status_output
  ;;
-h | --help | help)
  usage
  ;;
*)
  usage >&2
  exit 2
  ;;
esac
