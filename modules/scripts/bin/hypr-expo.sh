#!/usr/bin/env bash
set -euo pipefail

# Lightweight replacement entrypoint for the old hyprexpo toggle.
# This does not reproduce the compositor plugin rendering. It routes to the
# active shell's window overview surface instead.

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
