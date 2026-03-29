#!/usr/bin/env bash
# ==============================================================================
# Script: sunsetr-scheduler-loop.sh
# Description: Integrated background loop for sunsetr preset sync
# ==============================================================================
set -euo pipefail

CHECK_INTERVAL=60

log() {
    printf '[sunsetr-scheduler] %s\n' "$*"
}

export PATH="$HOME/.local/bin:$HOME/bin:/usr/local/bin:/usr/bin:/bin:${PATH:-}"

log "Starting scheduler loop..."
sleep 5

while true; do
    sunsetr-scheduler >/dev/null 2>&1 || true
    sleep $CHECK_INTERVAL
done
