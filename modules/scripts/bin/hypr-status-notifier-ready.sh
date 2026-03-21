#!/usr/bin/env bash
# ==============================================================================
# Script: hypr-status-notifier-ready.sh
# Description: Wait for StatusNotifierWatcher before Hyprland tray applets start.
# ==============================================================================

set -euo pipefail

LOG_TAG="hypr-status-notifier-ready"

log() { printf '[%s] %s\n' "$LOG_TAG" "$*" >&2; }

if ! command -v gdbus >/dev/null 2>&1; then
  log "gdbus not found; skipping watcher readiness gate"
  exit 0
fi

deadline=$((SECONDS + 20))
while (( SECONDS < deadline )); do
  if gdbus introspect \
    --session \
    --dest org.kde.StatusNotifierWatcher \
    --object-path /StatusNotifierWatcher \
    >/dev/null 2>&1; then
    log "StatusNotifierWatcher is ready"
    exit 0
  fi
  sleep 1
done

log "StatusNotifierWatcher was not ready before timeout; continuing anyway"
