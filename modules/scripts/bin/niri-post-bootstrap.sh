#!/usr/bin/env bash
# Lightweight post-bootstrap tasks for Niri session.

set -euo pipefail

LOG_TAG="niri-post-bootstrap"

log() { printf '[%s] %s\n' "$LOG_TAG" "$*"; }

if command -v notify-send >/dev/null 2>&1; then
  notify-send -t 1800 "Niri" "Session ready" >/dev/null 2>&1 || true
fi

log "niri-post-bootstrap completed"
