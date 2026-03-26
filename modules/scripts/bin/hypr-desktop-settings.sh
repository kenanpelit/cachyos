#!/usr/bin/env bash
# ==============================================================================
# Script: hypr-desktop-settings.sh
# Description: Apply GTK, icon, and cursor settings after Hyprland startup.
# ==============================================================================

set -euo pipefail

LOG_TAG="hypr-desktop-settings"

log() { printf '[%s] %s\n' "$LOG_TAG" "$*"; }
warn() { printf '[%s] WARN: %s\n' "$LOG_TAG" "$*" >&2; }

case "${HYPR_SYNC_GNOME_APPEARANCE:-1}" in
  1|true|yes|on)
    ;;
  0|false|no|off)
    log "GNOME appearance sync disabled; skipping"
    exit 0
    ;;
  *)
    warn "unrecognized HYPR_SYNC_GNOME_APPEARANCE=${HYPR_SYNC_GNOME_APPEARANCE}; treating as enabled"
    ;;
esac

if ! command -v gsettings >/dev/null 2>&1; then
  log "gsettings not found; skipping desktop settings sync"
  exit 0
fi

gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark' >/dev/null 2>&1 || warn "failed to set color-scheme"
gsettings set org.gnome.desktop.interface gtk-theme "${GTK_THEME:-catppuccin-mocha-mauve-standard+default}" >/dev/null 2>&1 || warn "failed to set gtk-theme"
gsettings set org.gnome.desktop.interface icon-theme "${XDG_ICON_THEME:-${ICON_THEME:-kora}}" >/dev/null 2>&1 || warn "failed to set icon-theme"
gsettings set org.gnome.desktop.interface cursor-theme "${XCURSOR_THEME:-capitaine-cursors}" >/dev/null 2>&1 || warn "failed to set cursor-theme"

log "desktop settings sync completed"
