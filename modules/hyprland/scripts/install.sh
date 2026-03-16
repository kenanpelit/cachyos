#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
MODULE_DIR="$(cd -- "${SCRIPT_DIR}/.." && pwd)"

"${MODULE_DIR}/scripts/render-theme.sh"

if command -v systemctl >/dev/null 2>&1; then
  systemctl --user daemon-reload >/dev/null 2>&1 || true
  systemctl --user disable --now gnome-keyring-secrets.service >/dev/null 2>&1 || true
  systemctl --user unmask gnome-keyring-daemon.socket gnome-keyring-daemon.service >/dev/null 2>&1 || true
  systemctl --user enable gnome-keyring-daemon.service >/dev/null 2>&1 || true
fi

if command -v dconf >/dev/null 2>&1; then
  dconf write /org/blueman/general/plugin-list "['!TransferService', '!GameControllerWakelock', '!PPPSupport', '!DhcpClient']" >/dev/null 2>&1 || true
fi
