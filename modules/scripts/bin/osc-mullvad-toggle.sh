#!/usr/bin/env bash
set -euo pipefail

SCRIPT_NAME="$(basename "$0")"
LOG_FILE="${XDG_CACHE_HOME:-$HOME/.cache}/osc-mullvad-toggle.log"
LOCK_FILE="${XDG_RUNTIME_DIR:-/tmp}/osc-mullvad-toggle.$(id -u).lock"

mkdir -p "$(dirname "$LOG_FILE")"
if ! touch "$LOG_FILE" 2>/dev/null; then
  LOG_FILE="${XDG_RUNTIME_DIR:-/tmp}/osc-mullvad-toggle.$(id -u).log"
  mkdir -p "$(dirname "$LOG_FILE")"
  touch "$LOG_FILE" 2>/dev/null || true
fi

log() {
  { printf "%s %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >>"$LOG_FILE"; } 2>/dev/null || true
}

die() {
  log "error: $*"
  printf "%s: %s\n" "$SCRIPT_NAME" "$*" >&2
  exit 1
}

usage() {
  cat <<USAGE
Usage:
  $SCRIPT_NAME [--no-blocky] [--dry-run] [--no-notify]

Options:
  --no-blocky     Toggle only Mullvad (without Blocky coupling)
  --dry-run       Print expected action, do not change state
  --no-notify     Disable desktop notifications
USAGE
}

trim_log() {
  if [[ -f "$LOG_FILE" ]] && [[ -w "$LOG_FILE" ]] && [[ "$(wc -l <"$LOG_FILE" 2>/dev/null || echo 0)" -gt 200 ]]; then
    local tmp_log
    tmp_log="$(mktemp "${XDG_RUNTIME_DIR:-/tmp}/osc-mullvad-toggle.log.XXXXXX" 2>/dev/null || true)"
    if [[ -n "${tmp_log:-}" ]]; then
      tail -n 200 "$LOG_FILE" >"$tmp_log" 2>/dev/null || true
      cat "$tmp_log" >"$LOG_FILE" 2>/dev/null || true
      rm -f "$tmp_log" 2>/dev/null || true
    fi
  fi
}

resolve_osc_mullvad() {
  if [[ -n "${OSC_MULLVAD_BIN:-}" ]] && [[ -x "${OSC_MULLVAD_BIN}" ]]; then
    return 0
  fi

  OSC_MULLVAD_BIN="$(command -v osc-mullvad 2>/dev/null || true)"
  if [[ -z "${OSC_MULLVAD_BIN}" ]]; then
    OSC_MULLVAD_BIN="$HOME/.local/bin/osc-mullvad"
  fi

  [[ -x "${OSC_MULLVAD_BIN}" ]] || die "osc-mullvad not found: ${OSC_MULLVAD_BIN}"
  log "resolved osc-mullvad: ${OSC_MULLVAD_BIN}"
}

notify_user() {
  [[ "${notify_enabled}" == "1" ]] || return 0
  command -v notify-send >/dev/null 2>&1 || return 0

  local vpn_connected="0"
  local blocky_active="0"
  local title=""
  local body=""
  local icon=""

  if command -v mullvad >/dev/null 2>&1 && mullvad status 2>/dev/null | grep -q "Connected"; then
    vpn_connected="1"
  fi

  if command -v systemctl >/dev/null 2>&1 && systemctl is-active --quiet blocky.service 2>/dev/null; then
    blocky_active="1"
  fi

  if [[ "$vpn_connected" == "1" ]]; then
    title="Mullvad"
    body="VPN connected"
    icon="network-vpn"
  elif [[ "$blocky_active" == "1" ]]; then
    title="Blocky"
    body="DNS filtering active"
    icon="network-error"
  else
    title="Network"
    body="Mullvad disconnected, Blocky off"
    icon="network-vpn-disconnected"
  fi

  notify-send -t 3500 -i "$icon" "$title" "$body" || true
}

preview_toggle() {
  local vpn_connected="0"
  local blocky_active="0"

  if command -v mullvad >/dev/null 2>&1 && mullvad status 2>/dev/null | grep -q "Connected"; then
    vpn_connected="1"
  fi

  if command -v systemctl >/dev/null 2>&1 && systemctl is-active --quiet blocky.service 2>/dev/null; then
    blocky_active="1"
  fi

  echo "[dry-run] current: mullvad=$([[ "$vpn_connected" == "1" ]] && echo connected || echo disconnected), blocky=$([[ "$blocky_active" == "1" ]] && echo on || echo off)"
  if [[ "${with_blocky}" == "1" ]]; then
    if [[ "$vpn_connected" == "1" ]]; then
      echo "[dry-run] next: disconnect Mullvad, start Blocky"
    else
      echo "[dry-run] next: stop Blocky, connect Mullvad"
    fi
  else
    if [[ "$vpn_connected" == "1" ]]; then
      echo "[dry-run] next: disconnect Mullvad"
    else
      echo "[dry-run] next: connect Mullvad"
    fi
  fi
}

run_toggle() {
  if [[ "${dry_run}" == "1" ]]; then
    preview_toggle
    return 0
  fi

  local cmd=("${OSC_MULLVAD_BIN}" toggle)
  [[ "${with_blocky}" == "1" ]] && cmd+=(--with-blocky)

  log "run: OSC_MULLVAD_NO_NOTIFY=1 ${cmd[*]}"
  if ! OSC_MULLVAD_NO_NOTIFY=1 "${cmd[@]}"; then
    local rc=$?
    if [[ "${with_blocky}" == "1" ]]; then
      log "toggle failed (rc=${rc}), running ensure fallback"
      OSC_MULLVAD_NO_NOTIFY=1 "${OSC_MULLVAD_BIN}" ensure --grace "${OSC_MULLVAD_TOGGLE_ENSURE_GRACE_SEC:-0}" || true
    fi
    return "$rc"
  fi

  if [[ "${with_blocky}" == "1" ]]; then
    OSC_MULLVAD_NO_NOTIFY=1 "${OSC_MULLVAD_BIN}" ensure --grace "${OSC_MULLVAD_TOGGLE_ENSURE_GRACE_SEC:-0}" || true
  fi
}

with_blocky="1"
dry_run="0"
notify_enabled="1"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --no-blocky) with_blocky="0" ;;
    --dry-run) dry_run="1" ;;
    --no-notify) notify_enabled="0" ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      usage >&2
      die "unknown option: $1"
      ;;
  esac
  shift
done

trim_log
log "triggered: uid=$(id -u) tty=$(tty 2>/dev/null || echo none)"
log "env: DISPLAY=${DISPLAY-} WAYLAND_DISPLAY=${WAYLAND_DISPLAY-} XDG_RUNTIME_DIR=${XDG_RUNTIME_DIR-}"

resolve_osc_mullvad

if command -v flock >/dev/null 2>&1; then
  lock_wait_sec="${OSC_MULLVAD_TOGGLE_LOCK_WAIT_SEC:-3}"
  [[ "$lock_wait_sec" =~ ^[0-9]+$ ]] || lock_wait_sec=3
  if ! { exec 9>"$LOCK_FILE"; } 2>/dev/null; then
    log "warn: lock file unavailable, continuing without lock: $LOCK_FILE"
  else
    flock -w "$lock_wait_sec" 9 || die "another toggle is already running"
  fi
fi

run_toggle
rc=$?
log "direct exit=${rc}"

if [[ "$rc" -eq 0 ]]; then
  notify_user
fi
exit "$rc"
