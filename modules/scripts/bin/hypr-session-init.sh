#!/usr/bin/env bash
# ==============================================================================
# Script: hypr-session-init
# Description: Start hyprland-session.target from inside the compositor.
#              Under UWSM, trust the pre-finalized session environment and only
#              fall back to runtime detection if critical compositor variables
#              are unexpectedly missing.
# Usage: hypr-session-init [--no-start-target]
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMMON_HELPER="${SCRIPT_DIR}/hypr-session-common.sh"
[[ -r "${COMMON_HELPER}" ]] || COMMON_HELPER="${SCRIPT_DIR}/hypr-session-common"
# shellcheck source=hypr-session-common.sh
source "${COMMON_HELPER}"

start_target=true

case "${1:-}" in
  ""|--start-target)
    ;;
  --no-start-target)
    start_target=false
    ;;
  *)
    echo "Usage: hypr-session-init [--no-start-target]" >&2
    exit 2
    ;;
esac

apply_session_env() {
  hypr_load_session_env

  export XDG_CURRENT_DESKTOP="${XDG_CURRENT_DESKTOP:-Hyprland}"
  export XDG_SESSION_TYPE="${XDG_SESSION_TYPE:-wayland}"
  export XDG_SESSION_DESKTOP="${XDG_SESSION_DESKTOP:-Hyprland}"
  export DESKTOP_SESSION="${DESKTOP_SESSION:-Hyprland}"
  export SYSTEMD_OFFLINE="${SYSTEMD_OFFLINE:-0}"
}

normalize_session_paths() {
  hypr_normalize_session_paths
}

collect_env_vars() {
  hypr_collect_env_vars
}

sync_session_environment() {
  hypr_sync_session_environment
}

ensure_uwsm_runtime_environment() {
  hypr_detect_wayland_display
  hypr_detect_instance_signature
  hypr_sync_runtime_environment
}

start_session_target() {
  command -v systemctl >/dev/null 2>&1 || return 0
  systemctl --user start --no-block hyprland-session.target >/dev/null 2>&1 || true
}

main() {
  hypr_ensure_runtime_dir

  if hypr_session_under_uwsm; then
    export XDG_CURRENT_DESKTOP="${XDG_CURRENT_DESKTOP:-Hyprland}"
    export XDG_SESSION_TYPE="${XDG_SESSION_TYPE:-wayland}"
    export XDG_SESSION_DESKTOP="${XDG_SESSION_DESKTOP:-Hyprland}"
    export DESKTOP_SESSION="${DESKTOP_SESSION:-hyprland-uwsm}"
    export SYSTEMD_OFFLINE="${SYSTEMD_OFFLINE:-0}"
    if [[ -z "${WAYLAND_DISPLAY:-}" || -z "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]]; then
      ensure_uwsm_runtime_environment
    fi
  else
    apply_session_env
    normalize_session_paths
    hypr_detect_wayland_display
    hypr_detect_instance_signature
    sync_session_environment
  fi

  if [[ "$start_target" == "true" ]]; then
    start_session_target
  fi
}

main
