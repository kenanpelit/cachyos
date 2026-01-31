#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
CFG_SRC="${SCRIPT_DIR}/../dotfiles/blocky/config.yml"
CFG_DST="/etc/blocky/blocky.yml"
RESOLVCONF_SRC="/etc/blocky/resolvconf.conf"
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

if command -v resolvconf >/dev/null 2>&1; then
  ${SUDO} install -d -m 755 "/etc/blocky"
  ${SUDO} tee "${RESOLVCONF_SRC}" >/dev/null <<'RCF'
nameserver 127.0.0.1
nameserver ::1
RCF

  ${SUDO} install -d -m 755 "${OVERRIDE_DIR}"
  ${SUDO} tee "${OVERRIDE_DST}" >/dev/null <<'OVR'
[Service]
ExecStartPost=+ /bin/sh -c '/usr/bin/resolvconf -m 0 -x -a blocky < /etc/blocky/resolvconf.conf'
ExecStartPost=+ /usr/bin/resolvconf -u
ExecStopPost=+ /usr/bin/resolvconf -f -d blocky
ExecStopPost=+ /usr/bin/resolvconf -u
OVR
else
  echo "resolvconf not found; skipping DNS hook override" >&2
fi

${SUDO} systemctl daemon-reload
if ${SUDO} systemctl list-unit-files blocky.service >/dev/null 2>&1; then
  ${SUDO} systemctl enable --now blocky.service
else
  echo "blocky.service not found; install package first" >&2
fi
