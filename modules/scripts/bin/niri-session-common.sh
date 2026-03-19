#!/usr/bin/env bash
# Shared helpers for Niri session bootstrap scripts.

niri_session_env_file() {
  printf '%s\n' "${NIRI_SESSION_ENVIRONMENT_FILE:-$HOME/.config/environment.d/10-niri-env.conf}"
}

niri_session_env_dir() {
  printf '%s\n' "${NIRI_SESSION_ENVIRONMENT_DIR:-$HOME/.config/environment.d}"
}

niri_ensure_runtime_dir() {
  if [[ -z "${XDG_RUNTIME_DIR:-}" ]]; then
    export XDG_RUNTIME_DIR="/run/user/$(id -u)"
  fi
}

niri_parse_env_file() {
  local env_file="$1"
  local line key value

  [[ -r "$env_file" ]] || return 0

  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    [[ "${line#\#}" == "$line" ]] || continue
    [[ "$line" == *=* ]] || continue

    key="${line%%=*}"
    value="${line#*=}"
    [[ -n "$key" ]] || continue
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

niri_parse_env_dir() {
  local env_dir file
  local -a env_files=()

  env_dir="$(niri_session_env_dir)"
  env_files=(
    "${env_dir}/10-gtk.conf"
    "$(niri_session_env_file)"
    "${env_dir}/20-qt.conf"
    "${env_dir}/30-ollama.conf"
    "${env_dir}/99-dms-icons.conf"
  )

  for file in "${env_files[@]}"; do
    [[ -r "$file" ]] || continue
    niri_parse_env_file "$file"
  done
}

niri_load_session_env() {
  local kv key value

  while IFS= read -r kv; do
    key="${kv%%=*}"
    value="${kv#*=}"
    [[ -n "$key" ]] || continue
    export "$key=$value"
  done < <(niri_parse_env_dir)
}

niri_normalize_colon_list() {
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

niri_normalize_session_paths() {
  local default_path default_data_dirs

  default_path="${HOME}/.local/bin:${HOME}/bin:/usr/local/bin:/usr/bin:/bin:/usr/local/sbin:${HOME}/.local/share/flatpak/exports/bin:/var/lib/flatpak/exports/bin:/usr/lib/jvm/default/bin:/usr/bin/site_perl:/usr/bin/vendor_perl:/usr/bin/core_perl"
  PATH="$(niri_normalize_colon_list "${PATH:-$default_path}")"
  export PATH

  default_data_dirs="${HOME}/.local/share/flatpak/exports/share:/var/lib/flatpak/exports/share:/usr/local/share:/usr/share"
  XDG_DATA_DIRS="$(niri_normalize_colon_list "${XDG_DATA_DIRS:-$default_data_dirs}")"
  export XDG_DATA_DIRS

  export XDG_CONFIG_DIRS="${XDG_CONFIG_DIRS:-/etc/xdg}"
}

niri_detect_wayland_display() {
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

niri_session_under_uwsm() {
  [[ -n "${UWSM_ID:-}" ]] \
    || [[ -n "${UWSM_FINALIZE_VARNAMES:-}" ]] \
    || [[ -n "${UWSM_WAIT_VARNAMES:-}" ]] \
    || [[ "${DESKTOP_SESSION:-}" == *-uwsm* ]] \
    || [[ "${GDMSESSION:-}" == *-uwsm* ]]
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

niri_sync_session_environment() {
  niri_sync_environment_vars niri_collect_env_vars
}

niri_sync_runtime_environment() {
  niri_sync_environment_vars niri_collect_runtime_env_vars
}
