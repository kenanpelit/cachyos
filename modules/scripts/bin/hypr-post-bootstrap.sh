#!/usr/bin/env bash
# ==============================================================================
# Script: hypr-post-bootstrap
# Description: Late Hyprland session polish for shell startup, cursor sync and
#              delayed portal orchestration.
# Usage: hypr-post-bootstrap
# ==============================================================================

set -euo pipefail

LOG_TAG="hypr-post-bootstrap"

log() { printf '[%s] %s\n' "$LOG_TAG" "$*"; }
warn() { printf '[%s] WARN: %s\n' "$LOG_TAG" "$*" >&2; }

export PATH="$HOME/.local/bin:$HOME/bin:/usr/local/bin:/usr/bin:/bin:${PATH:-}"

load_session_env() {
  local env_file line key value
  env_file="${HYPR_SESSION_ENVIRONMENT_FILE:-$HOME/.config/environment.d/10-hyprland.conf}"

  [[ -r "$env_file" ]] || return 0

  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    [[ "${line#\#}" == "$line" ]] || continue
    [[ "$line" == *=* ]] || continue

    key="${line%%=*}"
    value="${line#*=}"
    value="${value//\$\{HOME\}/$HOME}"
    value="${value//\$HOME/$HOME}"
    export "$key=$value"
  done <"$env_file"
}

queue_dconf_sync() {
  command -v gsettings >/dev/null 2>&1 || return 0

  (
    gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark' >/dev/null 2>&1 || true
    gsettings set org.gnome.desktop.interface gtk-theme "${GTK_THEME:-catppuccin-mocha-mauve-standard+default}" >/dev/null 2>&1 || true
    gsettings set org.gnome.desktop.interface icon-theme "${XDG_ICON_THEME:-${ICON_THEME:-kora}}" >/dev/null 2>&1 || true
    gsettings set org.gnome.desktop.interface cursor-theme "${XCURSOR_THEME:-capitaine-cursors}" >/dev/null 2>&1 || true
  ) &
  disown || true
}

ensure_hypr_env() {
  : "${XDG_RUNTIME_DIR:="/run/user/$(id -u)"}"

  if [[ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]]; then
    return 0
  fi

  local sig
  sig="$(ls "$XDG_RUNTIME_DIR"/hypr 2>/dev/null | head -n1 || true)"
  if [[ -n "${sig:-}" ]]; then
    export HYPRLAND_INSTANCE_SIGNATURE="$sig"
  fi
}

run_if_present() {
  local cmd="$1"
  shift || true

  if command -v "$cmd" >/dev/null 2>&1; then
    if "$cmd" "$@"; then
      log "$cmd $*"
    else
      warn "$cmd $* failed; continuing"
    fi
  else
    warn "$cmd not found; skipping"
  fi
}

start_user_service_if_present() {
  local svc="$1"

  command -v systemctl >/dev/null 2>&1 || return 0

  if ! systemctl --user show -p LoadState "$svc" >/dev/null 2>&1; then
    warn "$svc is not installed; skipping"
    return 0
  fi

  if command -v timeout >/dev/null 2>&1; then
    timeout 3s systemctl --user start "$svc" >/dev/null 2>&1 || true
  else
    systemctl --user start "$svc" >/dev/null 2>&1 || true
  fi
}

main() {
  load_session_env
  ensure_hypr_env || true
  queue_dconf_sync

  run_if_present osc-shell ensure

  if command -v hyprctl >/dev/null 2>&1; then
    if hyprctl setcursor "${XCURSOR_THEME:-capitaine-cursors}" "${XCURSOR_SIZE:-24}" >/dev/null 2>&1; then
      log "hyprctl setcursor ${XCURSOR_THEME:-capitaine-cursors} ${XCURSOR_SIZE:-24}"
    else
      warn "hyprctl setcursor failed; continuing"
    fi
  else
    warn "hyprctl not found; skipping cursor sync"
  fi

  start_user_service_if_present xdg-desktop-portal-delayed.service

  log "hypr-post-bootstrap completed."
}

main
