#!/usr/bin/env bash
# ==============================================================================
# Script: status-notifier-ready
# Description: Shared readiness gate that waits for the StatusNotifierWatcher on the session bus.
# Usage: status-notifier-ready
# ==============================================================================

set -euo pipefail

LOG_TAG="${STATUS_NOTIFIER_READY_LOG_TAG:-status-notifier-ready}"
WATCHER_DEST="${STATUS_NOTIFIER_READY_DEST:-org.kde.StatusNotifierWatcher}"
WATCHER_PATH="${STATUS_NOTIFIER_READY_OBJECT_PATH:-/StatusNotifierWatcher}"
TIMEOUT_SECS="${STATUS_NOTIFIER_READY_TIMEOUT_SECS:-20}"
SLEEP_SECS="${STATUS_NOTIFIER_READY_SLEEP_SECS:-1}"

log() { printf '[%s] %s\n' "$LOG_TAG" "$*" >&2; }

if ! command -v gdbus >/dev/null 2>&1; then
  log "gdbus not found; skipping watcher readiness gate"
  exit 0
fi

deadline=$((SECONDS + TIMEOUT_SECS))
while (( SECONDS < deadline )); do
  if gdbus introspect \
    --session \
    --dest "$WATCHER_DEST" \
    --object-path "$WATCHER_PATH" \
    >/dev/null 2>&1; then
    log "StatusNotifierWatcher is ready"
    exit 0
  fi
  sleep "$SLEEP_SECS"
done

log "StatusNotifierWatcher was not ready before timeout; continuing anyway"
