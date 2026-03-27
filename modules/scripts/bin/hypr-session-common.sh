#!/usr/bin/env bash
# ==============================================================================
# Script: hypr-session-common.sh
# Description: Shared environment/bootstrap helpers for Hyprland session scripts.
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMMON_HELPER="${SCRIPT_DIR}/wayland-session-common.sh"
[[ -r "${COMMON_HELPER}" ]] || COMMON_HELPER="${SCRIPT_DIR}/wayland-session-common"
# shellcheck source=wayland-session-common.sh
source "${COMMON_HELPER}"

hypr_log_warn() {
  printf '[hypr-session-common] WARN: %s\n' "$*" >&2
}

hypr_session_env_file() {
  printf '%s\n' "${HYPR_SESSION_ENVIRONMENT_FILE:-$HOME/.config/session-env/hyprland/10-hyprland.conf}"
}

hypr_session_env_dir() {
  printf '%s\n' "${HYPR_SESSION_ENVIRONMENT_DIR:-$HOME/.config/environment.d}"
}

hypr_session_env_manifest() {
  printf '%s\n' "${HYPR_SESSION_ENVIRONMENT_MANIFEST:-$(hypr_session_env_dir)/hyprland-session.envlist}"
}

hypr_ensure_runtime_dir() {
  session_common_ensure_runtime_dir
}

hypr_parse_env_file() {
  session_common_parse_env_file "$@"
}

hypr_parse_env_dir() {
  local env_dir manifest raw_entry entry env_file
  local optional=false
  local -a env_files=()

  env_dir="$(hypr_session_env_dir)"
  manifest="$(hypr_session_env_manifest)"

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
      hypr_log_warn "missing required session env entry: ${entry}"
    done <"${manifest}"
  fi

  if [[ ${#env_files[@]} -eq 0 ]]; then
    env_file="$(hypr_session_env_file)"
    env_files=(
      "${env_dir}/00-wayland.conf"
      "${env_dir}/10-gtk.conf"
      "${env_dir}/20-qt.conf"
      "${env_file}"
    )
  fi

  session_common_parse_env_dir "${env_files[@]}"
}

hypr_load_session_env() {
  session_common_load_session_env hypr_parse_env_dir
}

hypr_normalize_colon_list() {
  session_common_normalize_colon_list "$1"
}

hypr_normalize_session_paths() {
  session_common_normalize_session_paths
}

hypr_detect_wayland_display() {
  session_common_detect_wayland_display
}

hypr_pick_instance_signature() {
  local hypr_root candidate candidate_score=-1 dir newest_mtime=-1 mtime
  local lock_file lock_pid lock_display score comm

  hypr_root="${XDG_RUNTIME_DIR}/hypr"
  [[ -d "$hypr_root" ]] || return 0

  for dir in "$hypr_root"/*; do
    [[ -d "$dir" ]] || continue
    [[ -S "$dir/.socket.sock" || -S "$dir/.socket2.sock" ]] || continue

    lock_file="$dir/hyprland.lock"
    lock_pid=""
    lock_display=""
    score=0

    if [[ -r "$lock_file" ]]; then
      IFS= read -r lock_pid <"$lock_file" || true
      lock_display="$(sed -n '2p' "$lock_file" 2>/dev/null || true)"
    fi

    if [[ -n "${WAYLAND_DISPLAY:-}" && -n "$lock_display" && "$lock_display" == "$WAYLAND_DISPLAY" ]]; then
      score=3
    fi

    if [[ -n "$lock_pid" && "$lock_pid" =~ ^[0-9]+$ ]] && kill -0 "$lock_pid" 2>/dev/null; then
      comm="$(ps -p "$lock_pid" -o comm= 2>/dev/null | tr -d '[:space:]')"
      if [[ "$comm" == "Hyprland" ]]; then
        (( score < 2 )) && score=2
        if [[ -n "${WAYLAND_DISPLAY:-}" && -n "$lock_display" && "$lock_display" == "$WAYLAND_DISPLAY" ]]; then
          score=4
        fi
      else
        (( score < 1 )) && score=1
      fi
    fi

    mtime="$(stat -c '%Y' "$dir" 2>/dev/null || printf '0')"
    if (( score > candidate_score || (score == candidate_score && mtime > newest_mtime) )); then
      candidate_score="$score"
      newest_mtime="$mtime"
      candidate="$(basename "$dir")"
    fi
  done

  if [[ -n "${candidate:-}" ]]; then
    printf '%s\n' "$candidate"
  fi
}

hypr_detect_instance_signature() {
  [[ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]] && return 0
  [[ -n "${XDG_RUNTIME_DIR:-}" ]] || return 0

  local sig
  sig="$(hypr_pick_instance_signature || true)"
  if [[ -n "${sig:-}" ]]; then
    export HYPRLAND_INSTANCE_SIGNATURE="$sig"
  fi
}

hypr_clear_foreign_session_env() {
  unset \
    GDK_BACKEND \
    NOCTALIA_STARTUP_HINT \
    WAYLAND_DISPLAY \
    DISPLAY \
    NIRI_SOCKET \
    HYPRLAND_INSTANCE_SIGNATURE \
    HYPRLAND_SOCKET \
    UWSM_WAIT_VARNAMES \
    UWSM_FINALIZE_VARNAMES \
    XDG_CURRENT_DESKTOP \
    XDG_SESSION_DESKTOP \
    XDG_MENU_PREFIX \
    DESKTOP_SESSION
}

hypr_session_under_uwsm() {
  session_common_under_uwsm
}

hypr_collect_env_vars() {
  local kv key
  local -a extra_vars=(
    WAYLAND_DISPLAY
    DISPLAY
    HYPRLAND_INSTANCE_SIGNATURE
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
  done < <(hypr_parse_env_dir)

  for var in "${extra_vars[@]}"; do
    [[ -n "${seen[$var]:-}" ]] && continue
    seen["$var"]=1
    printf '%s\n' "$var"
  done
}

hypr_collect_runtime_env_vars() {
  cat <<'EOF'
WAYLAND_DISPLAY
DISPLAY
HYPRLAND_INSTANCE_SIGNATURE
SSH_AUTH_SOCK
XDG_CURRENT_DESKTOP
XDG_SESSION_TYPE
XDG_SESSION_DESKTOP
DESKTOP_SESSION
EOF
}

hypr_sync_environment_vars() {
  session_common_sync_environment_vars "$1"
}

hypr_sync_session_environment() {
  hypr_sync_environment_vars hypr_collect_env_vars
}

hypr_sync_runtime_environment() {
  hypr_sync_environment_vars hypr_collect_runtime_env_vars
}
