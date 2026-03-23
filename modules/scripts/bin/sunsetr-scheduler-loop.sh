#!/usr/bin/env bash
# ==============================================================================
# Script: sunsetr-scheduler-loop.sh
# Description: Pure background loop for preset sync
# ==============================================================================
set -euo pipefail

SETTER_BIN="$HOME/.local/bin/sunsetr-set"
CHECK_INTERVAL=60

# Wait for sunsetr to be ready
sleep 5

while true; do
    # Check if sunsetr is running
    if sunsetr status >/dev/null 2>&1; then
        TARGET_PRESET=$($SETTER_BIN auto)
        CURRENT_ACTIVE=$(sunsetr status 2>/dev/null | grep "Active preset:" | awk '{print $NF}' || echo "default")
        
        if [[ "$TARGET_PRESET" != "$CURRENT_ACTIVE" ]]; then
            sunsetr preset "$TARGET_PRESET" >/dev/null 2>&1 || true
        fi
    fi
    sleep $CHECK_INTERVAL
done
