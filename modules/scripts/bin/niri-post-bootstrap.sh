#!/usr/bin/env bash
# Lightweight post-bootstrap tasks for Niri session.

set -u

if command -v gsettings >/dev/null 2>&1; then
  # Best-effort; do not fail startup if schemas are unavailable.
  gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark' >/dev/null 2>&1 || true
  gsettings set org.gnome.desktop.interface gtk-theme 'catppuccin-mocha-mauve-standard+default' >/dev/null 2>&1 || true
  gsettings set org.gnome.desktop.interface icon-theme 'kora' >/dev/null 2>&1 || true
  gsettings set org.gnome.desktop.interface cursor-theme 'catppuccin-mocha-dark-cursors' >/dev/null 2>&1 || true
fi

if command -v notify-send >/dev/null 2>&1; then
  notify-send -t 1800 "Niri" "Session ready" >/dev/null 2>&1 || true
fi

exit 0
