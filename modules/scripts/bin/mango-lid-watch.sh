#!/usr/bin/env bash
set -euo pipefail

log() {
  printf 'mango-lid-watch: %s\n' "$*"
}

resolve_state_file() {
  local candidate=""

  for candidate in /proc/acpi/button/lid/*/state; do
    [[ -f "$candidate" ]] || continue
    printf '%s\n' "$candidate"
    return 0
  done

  return 1
}

read_lid_state() {
  local state_file="$1"

  awk '{print tolower($NF)}' "$state_file" 2>/dev/null
}

wait_for_lid_open() {
  local state_file="$1"
  local state=""

  while true; do
    state="$(read_lid_state "$state_file" || true)"
    [[ "$state" != "closed" ]] && return 0
    sleep "${MANGO_LID_REARM_POLL_SEC:-1}"
  done
}

request_lock_and_suspend() {
  log "lid closed; requesting Noctalia lock-and-suspend"

  if osc-shell ipc call sessionMenu lockAndSuspend >/dev/null 2>&1; then
    log "Noctalia accepted lock-and-suspend request"
    return 0
  fi

  log "Noctalia lock-and-suspend IPC failed; falling back to lock + suspend"
  osc-shell ipc call lockScreen lock >/dev/null 2>&1 \
    || loginctl lock-session >/dev/null 2>&1 \
    || loginctl lock-sessions >/dev/null 2>&1 \
    || true

  sleep "${MANGO_LID_SUSPEND_DELAY_SEC:-1}"
  exec systemctl suspend
}

main() {
  local state_file=""
  local last_state=""
  local current_state=""

  state_file="${MANGO_LID_STATE_FILE:-}"
  if [[ -z "$state_file" ]]; then
    state_file="$(resolve_state_file)" || {
      log "no lid state file found under /proc/acpi/button/lid"
      exit 1
    }
  fi

  last_state="$(read_lid_state "$state_file" || true)"
  log "watching ${state_file} (initial=${last_state:-unknown})"

  while true; do
    sleep "${MANGO_LID_POLL_SEC:-0.25}"
    current_state="$(read_lid_state "$state_file" || true)"
    [[ -n "$current_state" ]] || continue
    [[ "$current_state" == "$last_state" ]] && continue

    log "state changed: ${last_state:-unknown} -> ${current_state}"

    if [[ "$current_state" == "closed" ]]; then
      request_lock_and_suspend || true
      wait_for_lid_open "$state_file"
      current_state="$(read_lid_state "$state_file" || echo open)"
      log "lid reopened; re-arming watcher"
    fi

    last_state="$current_state"
  done
}

main "$@"
