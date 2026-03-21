#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
MODULE_DIR="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
REPO_ROOT="$(cd -- "${MODULE_DIR}/../.." && pwd)"

# shellcheck source=/dev/null
source "${REPO_ROOT}/modules/base/lib/core.sh"

LEGACY_ENV_FILE="${USER_HOME}/.config/environment.d/10-hyprland.conf"

"${MODULE_DIR}/scripts/render-theme.sh"
"${MODULE_DIR}/scripts/render-monitors.sh"

run_as_user rm -f "${LEGACY_ENV_FILE}" 2>/dev/null || true

if command -v systemctl >/dev/null 2>&1; then
  run_as_user systemctl --user daemon-reload >/dev/null 2>&1 || true
  run_as_user systemctl --user disable --now gnome-keyring-secrets.service >/dev/null 2>&1 || true
  run_as_user systemctl --user unmask gnome-keyring-daemon.socket gnome-keyring-daemon.service >/dev/null 2>&1 || true
  run_as_user systemctl --user enable gnome-keyring-daemon.service >/dev/null 2>&1 || true
fi

if command -v dconf >/dev/null 2>&1; then
  run_as_user dconf write /org/blueman/general/plugin-list "['!TransferService', '!GameControllerWakelock', '!PPPSupport', '!DhcpClient']" >/dev/null 2>&1 || true
fi
