#!/usr/bin/env bash
# ==============================================================================
# Script: wayland-session-common.sh
# Description: Shared env parsing and runtime-dir helpers for Wayland sessions.
# ==============================================================================

session_common_log_warn() {
  printf '[wayland-session-common] WARN: %s\n' "$*" >&2
}

session_common_ensure_runtime_dir() {
  if [[ -z "${XDG_RUNTIME_DIR:-}" ]]; then
    export XDG_RUNTIME_DIR="/run/user/$(id -u)"
  fi
}

session_common_parse_env_file() {
  local env_file="$1"
  local line key value

  [[ -r "$env_file" ]] || return 0

  while IFS= read -r line; do
    line="${line#"${line%%[![:space:]]*}"}"
    line="${line%"${line##*[![:space:]]}"}"
    [[ -n "$line" ]] || continue
    [[ "${line#\#}" == "$line" ]] || continue

    if [[ "$line" == export[[:space:]]* ]]; then
      line="${line#export }"
      line="${line#"${line%%[![:space:]]*}"}"
    fi

    if [[ "$line" != *=* ]]; then
      session_common_log_warn "ignoring unsupported env line in ${env_file}: ${line}"
      continue
    fi

    key="${line%%=*}"
    value="${line#*=}"
    key="${key#"${key%%[![:space:]]*}"}"
    key="${key%"${key##*[![:space:]]}"}"
    [[ -n "$key" ]] || continue
    if [[ ! "$key" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]; then
      session_common_log_warn "ignoring invalid env key in ${env_file}: ${key}"
      continue
    fi
    if [[ "$value" == \"*\" && "$value" == *\" ]]; then
      value="${value:1:${#value}-2}"
    elif [[ "$value" == \'*\' && "$value" == *\' ]]; then
      value="${value:1:${#value}-2}"
    fi
    value="${value//\$\{HOME\}/$HOME}"
    value="${value//\$HOME/$HOME}"
    printf '%s=%s\n' "$key" "$value"
  done <"$env_file"
}

session_common_parse_env_dir() {
  local file

  for file in "$@"; do
    [[ -r "$file" ]] || continue
    session_common_parse_env_file "$file"
  done
}

session_common_load_session_env() {
  local collector="$1"
  local kv key value

  while IFS= read -r kv; do
    key="${kv%%=*}"
    value="${kv#*=}"
    [[ -n "$key" ]] || continue
    export "$key=$value"
  done < <("$collector")
}

session_common_normalize_colon_list() {
  local value="$1"
  local expanded part
  local -a parts cleaned=()
  local -A seen=()

  expanded="${value//\$\{HOME\}/$HOME}"
  expanded="${expanded//\$HOME/$HOME}"
  IFS=':' read -r -a parts <<<"$expanded"

  for part in "${parts[@]}"; do
    [[ -n "$part" ]] || continue
    [[ -n "${seen[$part]:-}" ]] && continue
    seen["$part"]=1
    cleaned+=("$part")
  done

  IFS=':'
  printf '%s\n' "${cleaned[*]}"
}

session_common_normalize_session_paths() {
  local default_path default_data_dirs

  default_path="${HOME}/.local/bin:${HOME}/bin:/usr/local/bin:/usr/bin:/bin:/usr/local/sbin:${HOME}/.local/share/flatpak/exports/bin:/var/lib/flatpak/exports/bin:/usr/lib/jvm/default/bin:/usr/bin/site_perl:/usr/bin/vendor_perl:/usr/bin/core_perl"
  PATH="$(session_common_normalize_colon_list "${PATH:-$default_path}")"
  export PATH

  default_data_dirs="${HOME}/.local/share/flatpak/exports/share:/var/lib/flatpak/exports/share:/usr/local/share:/usr/share"
  XDG_DATA_DIRS="$(session_common_normalize_colon_list "${XDG_DATA_DIRS:-$default_data_dirs}")"
  export XDG_DATA_DIRS

  export XDG_CONFIG_DIRS="${XDG_CONFIG_DIRS:-/etc/xdg}"
}

session_common_detect_wayland_display() {
  [[ -n "${WAYLAND_DISPLAY:-}" ]] && return 0
  [[ -n "${XDG_RUNTIME_DIR:-}" ]] || return 0

  local sock
  for sock in "${XDG_RUNTIME_DIR}"/wayland-*; do
    [[ -S "$sock" ]] || continue
    export WAYLAND_DISPLAY
    WAYLAND_DISPLAY="$(basename "$sock")"
    return 0
  done
}

session_common_detect_x11_display() {
  [[ -n "${DISPLAY:-}" ]] && return 0

  local sock candidate display
  local -a candidates=()

  shopt -s nullglob
  for sock in /tmp/.X11-unix/X*; do
    [[ -S "$sock" ]] || continue
    candidates+=("$sock")
  done
  shopt -u nullglob

  [[ ${#candidates[@]} -gt 0 ]] || return 0

  candidate="${candidates[0]}"
  if [[ ${#candidates[@]} -gt 1 ]]; then
    candidate="$(ls -1t /tmp/.X11-unix/X* 2>/dev/null | head -n 1 || true)"
    [[ -n "${candidate:-}" ]] || candidate="${candidates[0]}"
    session_common_log_warn "multiple X11 displays detected; using ${candidate}"
  fi

  display="$(basename "${candidate}")"
  display=":${display#X}"
  export DISPLAY="${display}"
}

session_common_under_uwsm() {
  [[ -n "${UWSM_ID:-}" ]] \
    || [[ -n "${UWSM_FINALIZE_VARNAMES:-}" ]] \
    || [[ -n "${UWSM_WAIT_VARNAMES:-}" ]] \
    || [[ "${DESKTOP_SESSION:-}" == *-uwsm* ]] \
    || [[ "${GDMSESSION:-}" == *-uwsm* ]]
}

session_common_sync_environment_vars() {
  local collector="$1"
  local -a env_vars=()
  local -a set_args=()
  local var value

  while IFS= read -r var; do
    [[ -n "$var" ]] || continue
    value="${!var-}"
    [[ -n "$value" ]] || continue
    env_vars+=("$var")
    set_args+=("${var}=${value}")
  done < <("$collector")

  [[ ${#env_vars[@]} -gt 0 ]] || return 0

  if command -v systemctl >/dev/null 2>&1; then
    systemctl --user import-environment "${env_vars[@]}" >/dev/null 2>&1 || true
    systemctl --user set-environment "${set_args[@]}" >/dev/null 2>&1 || true
  fi

  if command -v dbus-update-activation-environment >/dev/null 2>&1; then
    dbus-update-activation-environment --systemd "${env_vars[@]}" >/dev/null 2>&1 \
      || dbus-update-activation-environment --systemd --all >/dev/null 2>&1 \
      || true
  fi
}

session_common_unset_manager_env() {
  [[ $# -gt 0 ]] || return 0
  command -v systemctl >/dev/null 2>&1 || return 0
  systemctl --user unset-environment "$@" >/dev/null 2>&1 || true
}

session_common_set_manager_env() {
  [[ $# -gt 0 ]] || return 0
  command -v systemctl >/dev/null 2>&1 || return 0
  systemctl --user set-environment "$@" >/dev/null 2>&1 || true
}
