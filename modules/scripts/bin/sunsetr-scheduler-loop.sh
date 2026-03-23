#!/usr/bin/env bash
# ==============================================================================
# Script: sunsetr-scheduler-loop.sh
# Description: Enhanced background loop for preset sync with logging
# ==============================================================================
set -euo pipefail

SETTER_BIN="$HOME/.local/bin/sunsetr-set"
CHECK_INTERVAL=60

log() {
    printf '[sunsetr-scheduler-loop] %s\n' "$*"
}

log "Starting scheduler loop..."

# Wait for sunsetr to be ready
sleep 5

while true; do
    # 1. Check if sunsetr daemon is alive
    if sunsetr status >/dev/null 2>&1; then
        # 2. Get target preset based on time
        TARGET_PRESET=$($SETTER_BIN auto | tr -d '[:space:]')
        
        # 3. Get current active preset (natively)
        # We look for the line "Active preset: <name>"
        # Using grep -o to extract exactly what follows the colon
        CURRENT_ACTIVE=$(sunsetr status 2>/dev/null | grep "Active preset:" | sed 's/.*Active preset: //' | tr -d '[:space:]' || echo "default")
        
        if [[ -n "$TARGET_PRESET" && "$TARGET_PRESET" != "$CURRENT_ACTIVE" ]]; then
            log "Time-based sync: $CURRENT_ACTIVE -> $TARGET_PRESET"
            sunsetr preset "$TARGET_PRESET" >/dev/null 2>&1 || log "ERROR: Failed to set preset $TARGET_PRESET"
        fi
    else
        log "WARN: Sunsetr daemon not responding."
    fi
    
    sleep $CHECK_INTERVAL
done
