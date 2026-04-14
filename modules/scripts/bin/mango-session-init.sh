#!/usr/bin/env bash
# ==============================================================================
# Script: mango-session-init
# Description: Compatibility helper for manual/MangoWM fallback startup and
#              runtime environment sync.
# Usage: mango-session-init [--no-start-target]
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMMON_HELPER="${SCRIPT_DIR}/mango-session-common.sh"
[[ -r "${COMMON_HELPER}" ]] || COMMON_HELPER="${SCRIPT_DIR}/mango-session-common"
# shellcheck source=mango-session-common.sh
source "${COMMON_HELPER}"

start_target=true

log_warn() {
  local message="$1"
  printf '[mango-session-init] WARN: %s\n' "$message" >&2
  if command -v logger >/dev/null 2>&1; then
    logger -t mango-session-init -- "WARN: $message" >/dev/null 2>&1 || true
  fi
}

log_notice() {
  local message="$1"
  printf '[mango-session-init] NOTICE: %s\n' "$message" >&2
  if command -v logger >/dev/null 2>&1; then
    logger -t mango-session-init -- "NOTICE: $message" >/dev/null 2>&1 || true
  fi
}

case "${1:-}" in
  ""|--start-target)
    ;;
  --no-start-target)
    start_target=false
    ;;
  *)
    echo "Usage: mango-session-init [--no-start-target]" >&2
    exit 2
    ;;
esac

apply_session_env() {
  mango_load_session_env
  mango_ensure_session_identity
  export SYSTEMD_OFFLINE="${SYSTEMD_OFFLINE:-0}"
}

normalize_session_paths() {
  mango_normalize_session_paths
}

sync_session_environment() {
  mango_sync_session_environment
}

ensure_uwsm_runtime_environment() {
  mango_detect_wayland_display
  session_common_detect_x11_display
  mango_sync_runtime_environment
}

start_session_target() {
  command -v systemctl >/dev/null 2>&1 || return 0
  systemctl --user start --no-block mangowm-session.target >/dev/null 2>&1 || true
}

main() {
  mango_ensure_runtime_dir

  if mango_session_under_uwsm; then
    apply_session_env
    normalize_session_paths
    export DESKTOP_SESSION="${DESKTOP_SESSION:-mango-uwsm}"
    export SYSTEMD_OFFLINE="${SYSTEMD_OFFLINE:-0}"
    if [[ -z "${XDG_CURRENT_DESKTOP:-}" || -z "${XDG_SESSION_TYPE:-}" || -z "${XDG_SESSION_DESKTOP:-}" ]]; then
      mango_ensure_session_identity
    fi
    if [[ -z "${WAYLAND_DISPLAY:-}" ]]; then
      log_warn "UWSM session missing WAYLAND_DISPLAY; falling back to runtime sync"
      ensure_uwsm_runtime_environment
    fi
    sync_session_environment
    mango_sync_runtime_environment
  else
    log_notice "UWSM not detected; using manual environment sync fallback"
    mango_clear_foreign_session_env
    apply_session_env
    normalize_session_paths
    mango_detect_wayland_display
    session_common_detect_x11_display
    sync_session_environment
  fi

  if [[ "${start_target}" == "true" ]]; then
    start_session_target
  fi
}

main
