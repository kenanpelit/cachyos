#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
SYS_SRC="${SCRIPT_DIR}/../dotfiles/systemd/system.slice.d/90-oomd.conf"
USR_SRC="${SCRIPT_DIR}/../dotfiles/systemd/user.slice.d/90-oomd.conf"

SYS_DST_DIR="/etc/systemd/system/system.slice.d"
USR_DST_DIR="/etc/systemd/system/user.slice.d"
SYS_DST="${SYS_DST_DIR}/90-oomd.conf"
USR_DST="${USR_DST_DIR}/90-oomd.conf"

SUDO=""
if [ "$(id -u)" -ne 0 ]; then
  if ! command -v sudo >/dev/null 2>&1; then
    echo "sudo is required" >&2
    exit 1
  fi
  SUDO="sudo"
fi

${SUDO} install -d "${SYS_DST_DIR}" "${USR_DST_DIR}"
${SUDO} install -m 644 "${SYS_SRC}" "${SYS_DST}"
${SUDO} install -m 644 "${USR_SRC}" "${USR_DST}"

${SUDO} systemctl daemon-reload
${SUDO} systemctl enable --now systemd-oomd.service
