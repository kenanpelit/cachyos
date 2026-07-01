#!/usr/bin/env bash
# ==============================================================================
# Script: margo-session-common.sh
# Description: Shared environment/bootstrap helpers for Margo session scripts.
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMMON_HELPER="${SCRIPT_DIR}/wayland-session-common.sh"
[[ -r "${COMMON_HELPER}" ]] || COMMON_HELPER="${SCRIPT_DIR}/wayland-session-common"
# shellcheck source=wayland-session-common.sh
source "${COMMON_HELPER}"

margo_log_warn() {
  printf '[margo-session-common] WARN: %s\n' "$*" >&2
}

margo_session_env_file() {
  printf '%s\n' "${MARGO_SESSION_ENVIRONMENT_FILE:-$HOME/.config/environment.d/10-margo-wayland.conf}"
}

margo_session_env_dir() {
  printf '%s\n' "${MARGO_SESSION_ENVIRONMENT_DIR:-$HOME/.config/environment.d}"
}

margo_session_env_manifest() {
  printf '%s\n' "${MARGO_SESSION_ENVIRONMENT_MANIFEST:-$(margo_session_env_dir)/margo-session.envlist}"
}

margo_ensure_runtime_dir() {
  session_common_ensure_runtime_dir
}

margo_parse_env_dir() {
  local env_dir manifest raw_entry entry env_file
  local optional=false
  local -a env_files=()

  env_dir="$(margo_session_env_dir)"
  manifest="$(margo_session_env_manifest)"

  if [[ -r "${manifest}" ]]; then
    while IFS= read -r raw_entry; do
      [[ -n "${raw_entry}" ]] || continue
      [[ "${raw_entry#\#}" == "${raw_entry}" ]] || continue

      optional=false
      entry="${raw_entry}"
      if [[ "${entry}" == \?* ]]; then
        optional=true
        entry="${entry#\?}"
      fi

      entry="${entry//\$\{HOME\}/$HOME}"
      entry="${entry//\$HOME/$HOME}"
      if [[ "${entry}" != /* ]]; then
        entry="${env_dir}/${entry}"
      fi

      if [[ -r "${entry}" ]]; then
        env_files+=("${entry}")
        continue
      fi

      $optional && continue
      margo_log_warn "missing required session env entry: ${entry}"
    done <"${manifest}"
  fi

  if [[ ${#env_files[@]} -eq 0 ]]; then
    env_file="$(margo_session_env_file)"
    env_files=(
      "${env_dir}/10-gtk.conf"
      "${env_dir}/20-qt.conf"
      "${env_file}"
    )
  fi

  session_common_parse_env_dir "${env_files[@]}"
}

margo_load_session_env() {
  session_common_load_session_env margo_parse_env_dir
}

margo_normalize_session_paths() {
  session_common_normalize_session_paths
}

margo_detect_wayland_display() {
  session_common_detect_wayland_display
}

margo_ensure_session_identity() {
  export XDG_CURRENT_DESKTOP="${XDG_CURRENT_DESKTOP:-margo}"
  export XDG_SESSION_TYPE="${XDG_SESSION_TYPE:-wayland}"
  export XDG_SESSION_DESKTOP="${XDG_SESSION_DESKTOP:-margo}"
  export DESKTOP_SESSION="${DESKTOP_SESSION:-margo}"
}

margo_clear_foreign_session_env() {
  unset \
    GDK_BACKEND \
    NOCTALIA_STARTUP_HINT \
    WAYLAND_DISPLAY \
    DISPLAY \
    UWSM_WAIT_VARNAMES \
    UWSM_FINALIZE_VARNAMES \
    XDG_CURRENT_DESKTOP \
    XDG_SESSION_DESKTOP \
    XDG_MENU_PREFIX \
    DESKTOP_SESSION
}

margo_session_under_uwsm() {
  session_common_under_uwsm
}

margo_collect_env_vars() {
  local kv key
  local -a extra_vars=(
    WAYLAND_DISPLAY
    DISPLAY
    XDG_SESSION_ID
    PATH
    XDG_DATA_DIRS
    XDG_CONFIG_DIRS
    SSH_AUTH_SOCK
    SYSTEMD_OFFLINE
    XDG_CURRENT_DESKTOP
    XDG_SESSION_TYPE
    XDG_SESSION_DESKTOP
    DESKTOP_SESSION
  )
  local var
  local -A seen=()

  while IFS= read -r kv; do
    key="${kv%%=*}"
    [[ -n "$key" ]] || continue
    [[ -n "${seen[$key]:-}" ]] && continue
    seen["$key"]=1
    printf '%s\n' "$key"
  done < <(margo_parse_env_dir)

  for var in "${extra_vars[@]}"; do
    [[ -n "${seen[$var]:-}" ]] && continue
    seen["$var"]=1
    printf '%s\n' "$var"
  done
}

margo_collect_runtime_env_vars() {
  cat <<'EOF'
WAYLAND_DISPLAY
DISPLAY
XDG_SESSION_ID
SSH_AUTH_SOCK
XDG_CURRENT_DESKTOP
XDG_SESSION_TYPE
XDG_SESSION_DESKTOP
DESKTOP_SESSION
EOF
}

margo_sync_environment_vars() {
  session_common_sync_environment_vars "$1"
}

margo_sync_session_environment() {
  margo_sync_environment_vars margo_collect_env_vars
}

margo_sync_runtime_environment() {
  margo_sync_environment_vars margo_collect_runtime_env_vars
}
