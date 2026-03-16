#!/usr/bin/env bash
# ==============================================================================
# Script: hypr-post-bootstrap
# Description: Late Hyprland session polish for shell startup, cursor sync and
#              delayed portal orchestration.
# Usage: hypr-post-bootstrap
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMMON_HELPER="${SCRIPT_DIR}/hypr-session-common.sh"
[[ -r "${COMMON_HELPER}" ]] || COMMON_HELPER="${SCRIPT_DIR}/hypr-session-common"
# shellcheck source=hypr-session-common.sh
source "${COMMON_HELPER}"

LOG_TAG="hypr-post-bootstrap"

log() { printf '[%s] %s\n' "$LOG_TAG" "$*"; }
warn() { printf '[%s] WARN: %s\n' "$LOG_TAG" "$*" >&2; }

export PATH="$HOME/.local/bin:$HOME/bin:/usr/local/bin:/usr/bin:/bin:${PATH:-}"

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
  hypr_ensure_runtime_dir
  hypr_detect_instance_signature
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
  hypr_load_session_env
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

  start_user_service_if_present hyprsunset.service
  start_user_service_if_present noctalia.service
  start_user_service_if_present xdg-desktop-portal-delayed.service

  log "hypr-post-bootstrap completed."
}

main
