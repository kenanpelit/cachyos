#!/usr/bin/env bash
# ==============================================================================
# Script: mango-session-common.sh
# Description: Shared environment/bootstrap helpers for MangoWM session scripts.
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMMON_HELPER="${SCRIPT_DIR}/wayland-session-common.sh"
[[ -r "${COMMON_HELPER}" ]] || COMMON_HELPER="${SCRIPT_DIR}/wayland-session-common"
# shellcheck source=wayland-session-common.sh
source "${COMMON_HELPER}"

mango_log_warn() {
  printf '[mango-session-common] WARN: %s\n' "$*" >&2
}

mango_session_env_file() {
  printf '%s\n' "${MANGO_SESSION_ENVIRONMENT_FILE:-$HOME/.config/session-env/mangowm/10-mangowm.conf}"
}

mango_session_env_dir() {
  printf '%s\n' "${MANGO_SESSION_ENVIRONMENT_DIR:-$HOME/.config/environment.d}"
}

mango_session_env_manifest() {
  printf '%s\n' "${MANGO_SESSION_ENVIRONMENT_MANIFEST:-$(mango_session_env_dir)/mangowm-session.envlist}"
}

mango_ensure_runtime_dir() {
  session_common_ensure_runtime_dir
}

mango_parse_env_dir() {
  local env_dir manifest raw_entry entry env_file
  local optional=false
  local -a env_files=()

  env_dir="$(mango_session_env_dir)"
  manifest="$(mango_session_env_manifest)"

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
      mango_log_warn "missing required session env entry: ${entry}"
    done <"${manifest}"
  fi

  if [[ ${#env_files[@]} -eq 0 ]]; then
    env_file="$(mango_session_env_file)"
    env_files=(
      "${env_dir}/00-wayland.conf"
      "${env_dir}/10-gtk.conf"
      "${env_dir}/20-qt.conf"
      "${env_file}"
    )
  fi

  session_common_parse_env_dir "${env_files[@]}"
}

mango_load_session_env() {
  session_common_load_session_env mango_parse_env_dir
}

mango_normalize_session_paths() {
  session_common_normalize_session_paths
}

mango_detect_wayland_display() {
  session_common_detect_wayland_display
}

mango_ensure_session_identity() {
  export XDG_CURRENT_DESKTOP="${XDG_CURRENT_DESKTOP:-mango}"
  export XDG_SESSION_TYPE="${XDG_SESSION_TYPE:-wayland}"
  export XDG_SESSION_DESKTOP="${XDG_SESSION_DESKTOP:-mango}"
  export DESKTOP_SESSION="${DESKTOP_SESSION:-mango}"
}

mango_clear_foreign_session_env() {
  unset \
    GDK_BACKEND \
    NOCTALIA_STARTUP_HINT \
    WAYLAND_DISPLAY \
    DISPLAY \
    NIRI_SOCKET \
    UWSM_WAIT_VARNAMES \
    UWSM_FINALIZE_VARNAMES \
    XDG_CURRENT_DESKTOP \
    XDG_SESSION_DESKTOP \
    XDG_MENU_PREFIX \
    DESKTOP_SESSION \
    HYPRLAND_INSTANCE_SIGNATURE \
    HYPRLAND_SOCKET \
    HYPRLAND_LOG_WLR \
    HYPRLAND_NO_RT \
    HYPRLAND_NO_SD_NOTIFY \
    HYPRLAND_NO_WATCHDOG_WARNING \
    HYPRCURSOR_THEME \
    HYPRCURSOR_SIZE
}

mango_session_under_uwsm() {
  session_common_under_uwsm
}

mango_collect_env_vars() {
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
  done < <(mango_parse_env_dir)

  for var in "${extra_vars[@]}"; do
    [[ -n "${seen[$var]:-}" ]] && continue
    seen["$var"]=1
    printf '%s\n' "$var"
  done
}

mango_collect_runtime_env_vars() {
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

mango_sync_environment_vars() {
  session_common_sync_environment_vars "$1"
}

mango_sync_session_environment() {
  mango_sync_environment_vars mango_collect_env_vars
}

mango_sync_runtime_environment() {
  mango_sync_environment_vars mango_collect_runtime_env_vars
}
