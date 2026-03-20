#!/usr/bin/env bash
# ==============================================================================
# Script: niri-post-bootstrap
# Description: Late Niri session polish for desktop settings and ready notification.
# Usage: niri-post-bootstrap
# ==============================================================================

set -euo pipefail

LOG_TAG="niri-post-bootstrap"

log() { printf '[%s] %s\n' "$LOG_TAG" "$*"; }

if [[ -x "${HOME}/.local/bin/niri-desktop-settings" ]]; then
  if ! "${HOME}/.local/bin/niri-desktop-settings"; then
    log "desktop settings sync reported an error"
  fi
fi

if command -v notify-send >/dev/null 2>&1; then
  notify-send -t 1800 "Niri" "Session ready" >/dev/null 2>&1 || true
fi

log "niri-post-bootstrap completed"
