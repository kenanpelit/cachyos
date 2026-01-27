#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
SERVICE_SRC="${SCRIPT_DIR}/../dotfiles/systemd/hblock-update.service"
TIMER_SRC="${SCRIPT_DIR}/../dotfiles/systemd/hblock-update.timer"
PROFILE_SRC="${SCRIPT_DIR}/../dotfiles/profile.d/hblock.sh"
SCRIPT_SRC="${SCRIPT_DIR}/hblock-update"

SERVICE_DST="/etc/systemd/system/hblock-update.service"
TIMER_DST="/etc/systemd/system/hblock-update.timer"
PROFILE_DST="/etc/profile.d/hblock.sh"
SCRIPT_DST="/usr/local/bin/hblock-update"

SUDO=""
if [ "$(id -u)" -ne 0 ]; then
  if ! command -v sudo >/dev/null 2>&1; then
    echo "sudo is required" >&2
    exit 1
  fi
  SUDO="sudo"
fi

${SUDO} install -m 644 "${SERVICE_SRC}" "${SERVICE_DST}"
${SUDO} install -m 644 "${TIMER_SRC}" "${TIMER_DST}"
${SUDO} install -m 644 "${PROFILE_SRC}" "${PROFILE_DST}"
${SUDO} install -m 755 "${SCRIPT_SRC}" "${SCRIPT_DST}"

${SUDO} systemctl daemon-reload
${SUDO} systemctl enable --now hblock-update.timer
