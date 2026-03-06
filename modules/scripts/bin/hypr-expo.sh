#!/usr/bin/env bash
# ==============================================================================
# Script: hypr-expo.sh
# Description: Lightweight replacement for hyprexpo toggle using shell overview.
# Usage: hypr-expo.sh [toggle|on|off|select]
# ==============================================================================
set -euo pipefail

cmd="${1:-toggle}"

case "$cmd" in
  toggle|on|enable|off|disable|select) ;;
  *)
    printf '%s\n' "usage: hypr-expo [toggle|on|off|select]" >&2
    exit 2
    ;;
esac

if command -v osc-shell >/dev/null 2>&1; then
  exec osc-shell ipc call dash toggle overview
fi

if command -v qs >/dev/null 2>&1; then
  exec qs -c noctalia-shell ipc call launcher windows
fi

if command -v dms >/dev/null 2>&1; then
  exec dms ipc call dash toggle overview
fi

printf '%s\n' "hypr-expo: no compatible overview backend found" >&2
exit 1
