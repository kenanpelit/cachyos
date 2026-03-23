#!/usr/bin/env bash
# ==============================================================================
# Script: sunsetr-scheduler-loop.sh
# Description: Integrated background loop for sunsetr preset sync
# ==============================================================================
set -euo pipefail

SCHEDULE_FILE="$HOME/.config/sunsetr/schedule.conf"
CHECK_INTERVAL=60

log() {
    printf '[sunsetr-scheduler] %s\n' "$*"
}

select_auto_preset() {
    [[ -f "$SCHEDULE_FILE" ]] || return 1
    
    local now_key=$(date +%H%M)
    now_key=$((10#$now_key))
    
    local selected=""
    local first_preset=""
    local last_preset=""
    
    # schedule.conf format: HH:MM PRESET_NAME
    while read -r start preset; do
        [[ -z "$start" || -z "$preset" ]] && continue
        local start_key=$(echo "$start" | tr -d ':')
        start_key=$((10#$start_key))
        
        [[ -z "$first_preset" ]] && first_preset="$preset"
        if (( now_key >= start_key )); then
            selected="$preset"
        fi
        last_preset="$preset"
    done < <(awk '/^[0-9]/ { print $1, $2 }' "$SCHEDULE_FILE")
    
    echo "${selected:-$last_preset}"
}

log "Starting scheduler loop..."
sleep 5

while true; do
    if sunsetr status >/dev/null 2>&1; then
        TARGET_PRESET=$(select_auto_preset)
        CURRENT_ACTIVE=$(sunsetr status 2>/dev/null | grep "Active preset:" | sed 's/.*Active preset: //' | tr -d '[:space:]' || echo "default")
        
        if [[ -n "$TARGET_PRESET" && "$TARGET_PRESET" != "$CURRENT_ACTIVE" ]]; then
            log "Syncing preset: $CURRENT_ACTIVE -> $TARGET_PRESET"
            sunsetr preset "$TARGET_PRESET" >/dev/null 2>&1 || true
        fi
    fi
    sleep $CHECK_INTERVAL
done
