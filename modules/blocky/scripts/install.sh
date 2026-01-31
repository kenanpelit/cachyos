#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
CFG_SRC="${SCRIPT_DIR}/../dotfiles/blocky/config.yml"
CFG_DST="/etc/blocky/config.yml"
OVERRIDE_DIR="/etc/systemd/system/blocky.service.d"
OVERRIDE_DST="${OVERRIDE_DIR}/override.conf"

SUDO=""
if [ "$(id -u)" -ne 0 ]; then
  if ! command -v sudo >/dev/null 2>&1; then
    echo "sudo is required" >&2
    exit 1
  fi
  SUDO="sudo"
fi

${SUDO} install -d -m 755 "$(dirname "${CFG_DST}")"
${SUDO} install -m 644 "${CFG_SRC}" "${CFG_DST}"

${SUDO} install -d -m 755 "${OVERRIDE_DIR}"
${SUDO} tee "${OVERRIDE_DST}" >/dev/null <<'OVR'
[Service]
ExecStartPost=+ /usr/bin/resolvconf -m 0 -x -a blocky <<'EOFX'
nameserver 127.0.0.1
nameserver ::1
EOFX
ExecStartPost=+ /usr/bin/resolvconf -u
ExecStopPost=+ /usr/bin/resolvconf -f -d blocky
ExecStopPost=+ /usr/bin/resolvconf -u
OVR

${SUDO} systemctl daemon-reload
${SUDO} systemctl enable --now blocky.service
