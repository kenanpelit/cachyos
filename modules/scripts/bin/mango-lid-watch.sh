#!/usr/bin/env bash
set -euo pipefail

log() {
  printf 'mango-lid-watch: %s\n' "$*"
}

upower_lid_state() {
  local response=""

  command -v gdbus >/dev/null 2>&1 || return 1

  response="$(
    gdbus call --system \
      --dest org.freedesktop.UPower \
      --object-path /org/freedesktop/UPower \
      --method org.freedesktop.DBus.Properties.Get \
      org.freedesktop.UPower LidIsClosed 2>/dev/null
  )" || return 1

  case "$response" in
    *"<true>"*) printf 'closed\n' ;;
    *"<false>"*) printf 'open\n' ;;
    *) return 1 ;;
  esac
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

handle_lid_state() {
  local state="$1"
  local last_state="$2"

  [[ -n "$state" ]] || return 0
  [[ "$state" != "$last_state" ]] || return 0

  log "state changed: ${last_state:-unknown} -> ${state}"

  if [[ "$state" == "closed" ]]; then
    request_lock_and_suspend || true
  fi
}

watch_with_upower() {
  local initial_state=""
  local last_state=""
  local line=""
  local event_state=""

  command -v gdbus >/dev/null 2>&1 || return 1

  initial_state="$(upower_lid_state)" || return 1
  last_state="$initial_state"
  log "watching UPower LidIsClosed (initial=${initial_state})"

  gdbus monitor --system \
    --dest org.freedesktop.UPower \
    --object-path /org/freedesktop/UPower 2>/dev/null |
    while IFS= read -r line; do
      [[ "$line" == *"PropertiesChanged"* && "$line" == *"LidIsClosed"* ]] || continue

      case "$line" in
        *"LidIsClosed': <true>"* | *'LidIsClosed": <true>'*) event_state="closed" ;;
        *"LidIsClosed': <false>"* | *'LidIsClosed": <false>'*) event_state="open" ;;
        *) continue ;;
      esac

      handle_lid_state "$event_state" "$last_state"
      last_state="$event_state"
    done

  return 1
}

watch_with_proc_polling() {
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
  log "UPower lid events unavailable; polling ${state_file} (initial=${last_state:-unknown})"

  while true; do
    sleep "${MANGO_LID_POLL_SEC:-0.25}"
    current_state="$(read_lid_state "$state_file" || true)"
    [[ -n "$current_state" ]] || continue
    handle_lid_state "$current_state" "$last_state"
    last_state="$current_state"
  done
}

main() {
  case "${MANGO_LID_BACKEND:-auto}" in
    auto)
      watch_with_upower || watch_with_proc_polling
      ;;
    upower)
      watch_with_upower
      ;;
    proc|poll|polling)
      watch_with_proc_polling
      ;;
    *)
      log "invalid MANGO_LID_BACKEND=${MANGO_LID_BACKEND}; expected auto, upower, or proc"
      exit 2
      ;;
  esac
}

main "$@"
