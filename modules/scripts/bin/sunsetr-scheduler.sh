#!/usr/bin/env bash
# ==============================================================================
# Script: sunsetr-scheduler.sh
# Description: One-shot preset sync for sunsetr based on the current schedule
# ==============================================================================
set -euo pipefail

SCHEDULE_FILE="${HOME}/.config/sunsetr/schedule.conf"

log() {
  printf '[sunsetr-scheduler] %s\n' "$*"
}

select_auto_preset() {
  [[ -f "$SCHEDULE_FILE" ]] || return 1

  local now_key selected last_preset
  now_key="$(date +%H%M)"
  now_key=$((10#$now_key))
  selected=""
  last_preset=""

  while read -r start preset; do
    [[ -n "$start" && -n "$preset" ]] || continue

    local start_key
    start_key="$(printf '%s' "$start" | tr -d ':')"
    start_key=$((10#$start_key))

    if (( now_key >= start_key )); then
      selected="$preset"
    fi
    last_preset="$preset"
  done < <(awk '/^[0-9]/ { print $1, $2 }' "$SCHEDULE_FILE")

  printf '%s\n' "${selected:-$last_preset}"
}

current_active_preset() {
  sunsetr status 2>/dev/null | awk -F'Active preset: ' '/Active preset:/ {print $2; exit}' | tr -d '[:space:]'
}

main() {
  command -v sunsetr >/dev/null 2>&1 || exit 0
  sunsetr status >/dev/null 2>&1 || exit 0

  local target_preset current_preset
  target_preset="$(select_auto_preset || true)"
  [[ -n "$target_preset" ]] || exit 0

  current_preset="$(current_active_preset || true)"
  if [[ -z "$current_preset" || "$current_preset" != "$target_preset" ]]; then
    log "Syncing preset: ${current_preset:-unknown} -> ${target_preset}"
    sunsetr preset "$target_preset" >/dev/null 2>&1 || true
  fi
}

main "$@"
