#!/usr/bin/env bash
# ==============================================================================
# Script: niri-session-init
# Description: Start niri-session.target from inside the compositor. Under
#              UWSM, trust the pre-finalized session environment and only fall
#              back to runtime detection if critical compositor variables are
#              unexpectedly missing.
# Usage: niri-session-init [--no-start-target]
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMMON_HELPER="${SCRIPT_DIR}/niri-session-common.sh"
[[ -r "${COMMON_HELPER}" ]] || COMMON_HELPER="${SCRIPT_DIR}/niri-session-common"
# shellcheck source=niri-session-common.sh
source "${COMMON_HELPER}"

start_target=true

log_warn() {
  local message="$1"
  printf '[niri-session-init] WARN: %s\n' "$message" >&2
  if command -v logger >/dev/null 2>&1; then
    logger -t niri-session-init -- "WARN: $message" >/dev/null 2>&1 || true
  fi
}

case "${1:-}" in
  ""|--start-target)
    ;;
  --no-start-target)
    start_target=false
    ;;
  *)
    echo "Usage: niri-session-init [--no-start-target]" >&2
    exit 2
    ;;
esac

apply_session_env() {
  niri_load_session_env
  niri_ensure_session_identity
  export SYSTEMD_OFFLINE="${SYSTEMD_OFFLINE:-0}"
}

normalize_session_paths() {
  niri_normalize_session_paths
}

sync_session_environment() {
  niri_sync_session_environment
}

ensure_uwsm_runtime_environment() {
  niri_detect_wayland_display
  niri_detect_socket
  niri_sync_runtime_environment
}

start_session_target() {
  command -v systemctl >/dev/null 2>&1 || return 0
  systemctl --user start --no-block niri-session.target >/dev/null 2>&1 || true
}

main() {
  niri_ensure_runtime_dir

  if niri_session_under_uwsm; then
    export XDG_CURRENT_DESKTOP="${XDG_CURRENT_DESKTOP:-niri}"
    export XDG_SESSION_TYPE="${XDG_SESSION_TYPE:-wayland}"
    export XDG_SESSION_DESKTOP="${XDG_SESSION_DESKTOP:-niri}"
    export DESKTOP_SESSION="${DESKTOP_SESSION:-niri-uwsm}"
    export GDMSESSION="${GDMSESSION:-niri-uwsm}"
    export SYSTEMD_OFFLINE="${SYSTEMD_OFFLINE:-0}"
    if [[ -z "${WAYLAND_DISPLAY:-}" || -z "${NIRI_SOCKET:-}" ]]; then
      log_warn "UWSM session missing runtime compositor variables; falling back to runtime sync"
      ensure_uwsm_runtime_environment
    fi
  else
    apply_session_env
    normalize_session_paths
    niri_detect_wayland_display
    niri_detect_socket
    sync_session_environment
  fi

  if [[ "$start_target" == "true" ]]; then
    start_session_target
  fi
}

main
