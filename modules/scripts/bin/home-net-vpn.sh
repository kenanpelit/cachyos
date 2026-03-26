#!/usr/bin/env bash
# ==============================================================================
# Script: home-net-vpn
# Description: Bring up the home Wi-Fi profile, then reconcile Mullvad/Blocky.
# Usage: home-net-vpn
# ==============================================================================

set -euo pipefail

LOG_TAG="home-net-vpn"
WIFI_CONNECTION_NAME="${OSC_LOGIN_WIFI_CONNECTION_NAME:-Ken_5}"
MULLVAD_SETTLE_TIMEOUT="${OSC_LOGIN_MULLVAD_SETTLE_TIMEOUT:-12}"
MULLVAD_SETTLE_POLL="${OSC_LOGIN_MULLVAD_SETTLE_POLL:-1}"
LOCK_FILE="${OSC_LOGIN_NET_VPN_LOCK_FILE:-${XDG_RUNTIME_DIR:-/tmp}/home-net-vpn.$(id -u).lock}"
WIFI_RESULT="pending"
MULLVAD_RESULT="pending"

export PATH="$HOME/.local/bin:$HOME/bin:/usr/local/bin:/usr/bin:/bin:${PATH:-}"

log() {
  printf '[%s] %s\n' "$LOG_TAG" "$*" >&2
}

die() {
  printf '[%s] ERROR: %s\n' "$LOG_TAG" "$*" >&2
  exit 1
}

notify_msg() {
  local title="$1"
  local body="$2"
  local urgency="${3:-normal}"
  local icon="${4:-network-wireless}"

  command -v notify-send >/dev/null 2>&1 || return 0
  notify-send -a "$LOG_TAG" -u "$urgency" -t 5000 -i "$icon" "$title" "$body" >/dev/null 2>&1 || true
}

handle_error() {
  local rc="$1"
  local line="$2"
  local body

  log "Failed at line ${line} with exit code ${rc}"
  printf -v body 'Wi-Fi: %s\nMullvad: %s\nExit code: %s' "$WIFI_RESULT" "$MULLVAD_RESULT" "$rc"
  notify_msg \
    "Home Login Setup Failed" \
    "$body" \
    "critical" \
    "dialog-error"
  exit "$rc"
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || die "Required command not found: $1"
}

wifi_connection_active() {
  nmcli -g NAME connection show --active 2>/dev/null | grep -Fxq "$WIFI_CONNECTION_NAME"
}

mullvad_state() {
  local status
  status="$(mullvad status 2>/dev/null || true)"

  case "$status" in
    *Connected*)
      echo connected
      ;;
    *Connecting*)
      echo connecting
      ;;
    *Disconnecting*)
      echo disconnecting
      ;;
    *)
      echo disconnected
      ;;
  esac
}

settle_mullvad_state() {
  local timeout="$MULLVAD_SETTLE_TIMEOUT"
  local poll="$MULLVAD_SETTLE_POLL"
  local elapsed=0
  local state

  [[ "$timeout" =~ ^[0-9]+$ ]] || timeout=12
  [[ "$poll" =~ ^[0-9]+$ ]] || poll=1
  (( poll > 0 )) || poll=1

  state="$(mullvad_state)"
  while [[ "$state" == "connecting" || "$state" == "disconnecting" ]]; do
    (( elapsed >= timeout )) && break
    sleep "$poll"
    elapsed=$((elapsed + poll))
    state="$(mullvad_state)"
  done

  printf '%s\n' "$state"
}

ensure_wifi_connection() {
  if wifi_connection_active; then
    WIFI_RESULT="${WIFI_CONNECTION_NAME} already active"
    log "NetworkManager connection already active: ${WIFI_CONNECTION_NAME}"
    return 0
  fi

  log "Activating NetworkManager connection: ${WIFI_CONNECTION_NAME}"
  nmcli connection up "$WIFI_CONNECTION_NAME" >/dev/null
  WIFI_RESULT="${WIFI_CONNECTION_NAME} connected"
}

ensure_mullvad_connection() {
  local state
  state="$(settle_mullvad_state)"

  case "$state" in
    connected)
      log "Mullvad already connected; reconciling Blocky fail-safe state"
      osc-mullvad ensure --grace 0 --poll 1
      MULLVAD_RESULT="already connected"
      ;;
    disconnected)
      log "Mullvad disconnected; enabling VPN with Blocky coupling"
      osc-mullvad toggle --with-blocky --no-notify
      state="$(settle_mullvad_state)"
      if [[ "$state" == "connected" ]]; then
        MULLVAD_RESULT="connected"
      else
        MULLVAD_RESULT="fallback active (${state})"
      fi
      ;;
    connecting|disconnecting)
      log "Mullvad still in transition; enforcing fail-safe state"
      osc-mullvad ensure --grace 10 --poll 1
      state="$(settle_mullvad_state)"
      case "$state" in
        connected)
          MULLVAD_RESULT="connected after transition"
          ;;
        disconnected)
          MULLVAD_RESULT="fallback active after transition"
          ;;
        *)
          MULLVAD_RESULT="still transitioning"
          ;;
      esac
      ;;
  esac
}

notify_success() {
  local title="Home Login Setup"
  local body
  local icon="network-wireless"

  printf -v body 'Wi-Fi: %s\nMullvad: %s' "$WIFI_RESULT" "$MULLVAD_RESULT"

  if [[ "$MULLVAD_RESULT" == connected* || "$MULLVAD_RESULT" == "already connected" ]]; then
    icon="network-vpn"
  elif [[ "$MULLVAD_RESULT" == fallback* ]]; then
    icon="network-server"
  elif [[ "$MULLVAD_RESULT" == "still transitioning" ]]; then
    icon="dialog-warning"
  fi

  notify_msg "$title" "$body" "normal" "$icon"
}

acquire_lock() {
  command -v flock >/dev/null 2>&1 || return 0

  exec 9>"$LOCK_FILE"
  if ! flock -n 9; then
    log "Another home-net-vpn instance is already running"
    notify_msg "Home Login Setup" "Another home-net-vpn run is already in progress." "low" "dialog-information"
    exit 0
  fi
}

main() {
  trap 'handle_error $? $LINENO' ERR

  require_command nmcli
  require_command mullvad
  require_command osc-mullvad
  acquire_lock

  ensure_wifi_connection
  ensure_mullvad_connection
  notify_success

  log "Post-login home network setup completed"
}

main "$@"
