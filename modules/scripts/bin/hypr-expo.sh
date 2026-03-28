#!/usr/bin/env bash
# ==============================================================================
# Script: hypr-expo.sh
# Description: Lightweight replacement for hyprexpo toggle using shell overview.
# Usage: hypr-expo.sh [toggle]
# ==============================================================================
set -euo pipefail

cmd="${1:-toggle}"

if [[ "$cmd" != "toggle" ]]; then
  printf '%s\n' "usage: hypr-expo [toggle]" >&2
  exit 2
fi

if command -v osc-shell >/dev/null 2>&1; then
  exec osc-shell ipc call dash toggle overview
fi

if command -v qs >/dev/null 2>&1; then
  exec qs -c noctalia-shell ipc call launcher windows
fi

printf '%s\n' "hypr-expo: no compatible overview backend found" >&2
exit 1
