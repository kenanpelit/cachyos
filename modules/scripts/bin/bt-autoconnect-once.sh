#!/usr/bin/env bash
# ==============================================================================
# Script: bt-autoconnect-once.sh
# Description: Bounded Bluetooth auto-connect helper for the user timer service.
# ==============================================================================

set -euo pipefail

ATTEMPTS="${BT_AUTOCONNECT_ATTEMPTS:-4}"
RETRY_DELAY="${BT_AUTOCONNECT_RETRY_DELAY:-8}"
AUDIO_WAIT_TIMEOUT="${BT_AUTOCONNECT_AUDIO_WAIT_TIMEOUT:-20}"

log() {
  printf '[bt-autoconnect-once] %s\n' "$*" >&2
}

resolve_bluetooth_toggle() {
  if command -v bluetooth_toggle >/dev/null 2>&1; then
    command -v bluetooth_toggle
    return 0
  fi

  if [[ -x "${HOME}/.local/bin/bluetooth_toggle" ]]; then
    printf '%s\n' "${HOME}/.local/bin/bluetooth_toggle"
    return 0
  fi

  return 1
}

wait_for_audio_stack() {
  command -v systemctl >/dev/null 2>&1 || return 0

  local deadline=$((SECONDS + AUDIO_WAIT_TIMEOUT))
  while ((SECONDS < deadline)); do
    if systemctl --user is-active --quiet pipewire.service &&
      systemctl --user is-active --quiet wireplumber.service; then
      return 0
    fi
    sleep 1
  done

  log "PipeWire/WirePlumber not fully active before timeout; continuing anyway"
  return 0
}

main() {
  local bt_cmd
  bt_cmd="$(resolve_bluetooth_toggle)" || {
    log "bluetooth_toggle not found"
    exit 1
  }

  wait_for_audio_stack

  local attempt=1
  while ((attempt <= ATTEMPTS)); do
    if "${bt_cmd}" --connect; then
      exit 0
    fi

    if ((attempt == ATTEMPTS)); then
      break
    fi

    log "Attempt ${attempt}/${ATTEMPTS} failed; retrying in ${RETRY_DELAY}s"
    sleep "${RETRY_DELAY}"
    ((attempt += 1))
  done

  log "Bluetooth auto-connect failed after ${ATTEMPTS} attempts"
  exit 1
}

main "$@"
