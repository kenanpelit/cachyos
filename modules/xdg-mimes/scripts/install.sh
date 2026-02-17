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

# Ensure directory handlers resolve to Nemo for file attach/open flows.
if command -v xdg-mime >/dev/null 2>&1; then
  if command -v nemo >/dev/null 2>&1 || [[ -f /usr/share/applications/nemo.desktop ]]; then
    xdg-mime default nemo.desktop inode/directory >/dev/null 2>&1 || true
    xdg-mime default nemo.desktop application/x-directory >/dev/null 2>&1 || true
  fi
fi

if command -v gio >/dev/null 2>&1; then
  if command -v nemo >/dev/null 2>&1 || [[ -f /usr/share/applications/nemo.desktop ]]; then
    gio mime inode/directory nemo.desktop >/dev/null 2>&1 || true
  fi
fi
