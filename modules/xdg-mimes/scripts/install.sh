#!/usr/bin/env bash
set -euo pipefail

if command -v update-desktop-database >/dev/null 2>&1; then
  update-desktop-database "${XDG_DATA_HOME:-$HOME/.local/share}/applications" >/dev/null 2>&1 || true
fi

if command -v xdg-settings >/dev/null 2>&1; then
  if [[ -f "${XDG_DATA_HOME:-$HOME/.local/share}/applications/brave-kenp.desktop" ]]; then
    xdg-settings set default-web-browser brave-kenp.desktop >/dev/null 2>&1 || true
  fi
fi
