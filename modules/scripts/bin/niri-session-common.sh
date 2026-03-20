#!/usr/bin/env bash
# Shared helpers for Niri session bootstrap scripts.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMMON_HELPER="${SCRIPT_DIR}/wayland-session-common.sh"
[[ -r "${COMMON_HELPER}" ]] || COMMON_HELPER="${SCRIPT_DIR}/wayland-session-common"
# shellcheck source=wayland-session-common.sh
source "${COMMON_HELPER}"

niri_session_env_file() {
  printf '%s\n' "${NIRI_SESSION_ENVIRONMENT_FILE:-$HOME/.config/session-env/niri/10-niri-env.conf}"
}

niri_session_env_dir() {
  printf '%s\n' "${NIRI_SESSION_ENVIRONMENT_DIR:-$HOME/.config/environment.d}"
}

niri_session_env_manifest() {
  printf '%s\n' "${NIRI_SESSION_ENVIRONMENT_MANIFEST:-$(niri_session_env_dir)/niri-session.envlist}"
}

niri_ensure_runtime_dir() {
  session_common_ensure_runtime_dir
}

niri_parse_env_file() {
  session_common_parse_env_file "$@"
}

niri_parse_env_dir() {
  local env_dir manifest entry env_file
  local -a env_files=()

  env_dir="$(niri_session_env_dir)"
  manifest="$(niri_session_env_manifest)"

  if [[ -r "${manifest}" ]]; then
    while IFS= read -r entry; do
      [[ -n "${entry}" ]] || continue
      [[ "${entry#\#}" == "${entry}" ]] || continue
      if [[ "${entry}" == /* ]]; then
        env_files+=("${entry}")
      else
        env_files+=("${env_dir}/${entry}")
      fi
    done <"${manifest}"
  fi

  if [[ ${#env_files[@]} -eq 0 ]]; then
    env_files=(
      "${env_dir}/00-wayland.conf"
      "${env_dir}/10-gtk.conf"
      "${env_dir}/20-qt.conf"
      "${env_dir}/30-ollama.conf"
      "${env_dir}/99-dms-icons.conf"
    )
  fi

  env_file="$(niri_session_env_file)"
  if [[ -r "${env_file}" ]]; then
    env_files+=("${env_file}")
  fi

  session_common_parse_env_dir "${env_files[@]}"
}

niri_load_session_env() {
  session_common_load_session_env niri_parse_env_dir
}

niri_normalize_colon_list() {
  session_common_normalize_colon_list "$1"
}

niri_normalize_session_paths() {
  session_common_normalize_session_paths
}

niri_detect_wayland_display() {
  session_common_detect_wayland_display
}

niri_detect_socket() {
  [[ -n "${NIRI_SOCKET:-}" ]] && [[ -S "${NIRI_SOCKET}" ]] && return 0
  [[ -n "${XDG_RUNTIME_DIR:-}" ]] || return 0
  [[ -n "${WAYLAND_DISPLAY:-}" ]] || return 0

  local sock
  shopt -s nullglob
  for sock in "${XDG_RUNTIME_DIR}/niri.${WAYLAND_DISPLAY}."*.sock; do
    [[ -S "$sock" ]] || continue
    export NIRI_SOCKET="$sock"
    break
  done
  shopt -u nullglob
}

niri_ensure_session_identity() {
  export XDG_CURRENT_DESKTOP="${XDG_CURRENT_DESKTOP:-niri}"
  export XDG_SESSION_TYPE="${XDG_SESSION_TYPE:-wayland}"
  export XDG_SESSION_DESKTOP="${XDG_SESSION_DESKTOP:-niri}"
  export DESKTOP_SESSION="${DESKTOP_SESSION:-niri}"
}

niri_clear_foreign_session_env() {
  unset \
    GDK_BACKEND \
    WAYLAND_DISPLAY \
    DISPLAY \
    NIRI_SOCKET \
    UWSM_WAIT_VARNAMES \
    UWSM_FINALIZE_VARNAMES \
    XDG_CURRENT_DESKTOP \
    XDG_SESSION_DESKTOP \
    XDG_MENU_PREFIX \
    DESKTOP_SESSION \
    GDMSESSION \
    HYPRLAND_INSTANCE_SIGNATURE \
    HYPRLAND_SOCKET \
    HYPRLAND_LOG_WLR \
    HYPRLAND_NO_RT \
    HYPRLAND_NO_SD_NOTIFY \
    HYPRLAND_NO_WATCHDOG_WARNING \
    HYPRCURSOR_THEME \
    HYPRCURSOR_SIZE
}

niri_session_under_uwsm() {
  session_common_under_uwsm
}

niri_collect_env_vars() {
  local kv key
  local -a extra_vars=(
    WAYLAND_DISPLAY
    DISPLAY
    NIRI_SOCKET
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
    GDMSESSION
  )
  local var
  local -A seen=()

  while IFS= read -r kv; do
    key="${kv%%=*}"
    [[ -n "$key" ]] || continue
    [[ -n "${seen[$key]:-}" ]] && continue
    seen["$key"]=1
    printf '%s\n' "$key"
  done < <(niri_parse_env_dir)

  for var in "${extra_vars[@]}"; do
    [[ -n "${seen[$var]:-}" ]] && continue
    seen["$var"]=1
    printf '%s\n' "$var"
  done
}

niri_collect_runtime_env_vars() {
  cat <<'EOF'
WAYLAND_DISPLAY
DISPLAY
NIRI_SOCKET
XDG_SESSION_ID
SSH_AUTH_SOCK
XDG_CURRENT_DESKTOP
XDG_SESSION_TYPE
XDG_SESSION_DESKTOP
DESKTOP_SESSION
GDMSESSION
EOF
}

niri_sync_environment_vars() {
  session_common_sync_environment_vars "$1"
}

niri_sync_session_environment() {
  niri_sync_environment_vars niri_collect_env_vars
}

niri_sync_runtime_environment() {
  niri_sync_environment_vars niri_collect_runtime_env_vars
}
