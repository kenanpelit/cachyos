#!/usr/bin/env bash
# Shared helpers for Hyprland session bootstrap scripts.

hypr_session_env_file() {
  printf '%s\n' "${HYPR_SESSION_ENVIRONMENT_FILE:-$HOME/.config/environment.d/10-hyprland.conf}"
}

hypr_ensure_runtime_dir() {
  if [[ -z "${XDG_RUNTIME_DIR:-}" ]]; then
    export XDG_RUNTIME_DIR="/run/user/$(id -u)"
  fi
}

hypr_parse_env_file() {
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
    value="${value//\$\{HOME\}/$HOME}"
    value="${value//\$HOME/$HOME}"
    printf '%s=%s\n' "$key" "$value"
  done <"$env_file"
}

hypr_load_session_env() {
  local env_file kv key value
  env_file="$(hypr_session_env_file)"

  while IFS= read -r kv; do
    key="${kv%%=*}"
    value="${kv#*=}"
    [[ -n "$key" ]] || continue
    export "$key=$value"
  done < <(hypr_parse_env_file "$env_file")
}

hypr_normalize_colon_list() {
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

hypr_normalize_session_paths() {
  local default_path default_data_dirs

  default_path="${HOME}/.local/share/zinit/polaris/bin:${HOME}/.local/bin:${HOME}/bin:${HOME}/.iptv/bin:/usr/local/bin:/usr/bin:/bin:/usr/local/sbin:${HOME}/.local/share/flatpak/exports/bin:/var/lib/flatpak/exports/bin:/usr/lib/jvm/default/bin:/usr/bin/site_perl:/usr/bin/vendor_perl:/usr/bin/core_perl:${HOME}/.local/share/go/bin"
  PATH="$(hypr_normalize_colon_list "${PATH:-$default_path}")"
  export PATH

  default_data_dirs="${HOME}/.local/share/flatpak/exports/share:/var/lib/flatpak/exports/share:/usr/local/share:/usr/share"
  XDG_DATA_DIRS="$(hypr_normalize_colon_list "${XDG_DATA_DIRS:-$default_data_dirs}")"
  export XDG_DATA_DIRS

  export XDG_CONFIG_DIRS="${XDG_CONFIG_DIRS:-/etc/xdg}"
}

hypr_detect_wayland_display() {
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

hypr_pick_instance_signature() {
  local hypr_root candidate dir newest_mtime=-1 mtime

  hypr_root="${XDG_RUNTIME_DIR}/hypr"
  [[ -d "$hypr_root" ]] || return 0

  for dir in "$hypr_root"/*; do
    [[ -d "$dir" ]] || continue
    [[ -S "$dir/.socket.sock" || -S "$dir/.socket2.sock" ]] || continue
    mtime="$(stat -c '%Y' "$dir" 2>/dev/null || printf '0')"
    if (( mtime > newest_mtime )); then
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

hypr_collect_env_vars() {
  local env_file kv key
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

  env_file="$(hypr_session_env_file)"
  while IFS= read -r kv; do
    key="${kv%%=*}"
    [[ -n "$key" ]] || continue
    [[ -n "${seen[$key]:-}" ]] && continue
    seen["$key"]=1
    printf '%s\n' "$key"
  done < <(hypr_parse_env_file "$env_file")

  for var in "${extra_vars[@]}"; do
    [[ -n "${seen[$var]:-}" ]] && continue
    seen["$var"]=1
    printf '%s\n' "$var"
  done
}

hypr_sync_session_environment() {
  local -a env_vars=()
  local -a set_args=()
  local var value

  while IFS= read -r var; do
    [[ -n "$var" ]] || continue
    value="${!var-}"
    [[ -n "$value" ]] || continue
    env_vars+=("$var")
    set_args+=("${var}=${value}")
  done < <(hypr_collect_env_vars)

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
