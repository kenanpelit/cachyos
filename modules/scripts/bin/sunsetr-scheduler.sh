#!/usr/bin/env bash
# ==============================================================================
# Script: sunsetr-scheduler.sh
# Description: Background scheduler loop for sunsetr daemon and presets
# ==============================================================================
set -euo pipefail

SUNSETR_BIN="/usr/bin/sunsetr"
SETTER_BIN="$HOME/.local/bin/sunsetr-set"
CHECK_INTERVAL=60

log() {
    printf '[sunsetr-scheduler] %s\n' "$*"
}

cleanup() {
    log "Shutting down..."
    kill $SUNSETR_PID 2>/dev/null || true
    exit 0
}

trap cleanup SIGINT SIGTERM

# 1. Start the main daemon in background
$SUNSETR_BIN &
SUNSETR_PID=$!
log "Started sunsetr daemon with PID $SUNSETR_PID"

# 2. Initial sync
$SETTER_BIN auto --apply --no-notify || true

# 3. Main loop
while true; do
    sleep $CHECK_INTERVAL
    
    # Health check
    if ! kill -0 $SUNSETR_PID 2>/dev/null; then
        log "ERROR: Sunsetr daemon (PID $SUNSETR_PID) is no longer running."
        exit 1
    fi
    
    # Periodic preset sync
    $SETTER_BIN auto --apply --no-notify || true
done
