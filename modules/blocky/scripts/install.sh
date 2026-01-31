#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
CFG_SRC="${SCRIPT_DIR}/../dotfiles/blocky/config.yml"
CFG_DST="/etc/blocky/blocky.yml"
OVERRIDE_DIR="/etc/systemd/system/blocky.service.d"
OVERRIDE_DST="${OVERRIDE_DIR}/override.conf"
NM_CONF_DIR="/etc/NetworkManager/conf.d"
NM_CONF_DST="${NM_CONF_DIR}/90-blocky-dns.conf"

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
# Allow binding to privileged port 53 without running as root.
AmbientCapabilities=CAP_NET_BIND_SERVICE
CapabilityBoundingSet=CAP_NET_BIND_SERVICE
NoNewPrivileges=true
OVR

if command -v setcap >/dev/null 2>&1; then
  ${SUDO} setcap cap_net_bind_service=+ep /usr/bin/blocky || true
else
  echo "setcap not found; port 53 may require root or systemd caps" >&2
fi

${SUDO} systemctl daemon-reload
if ${SUDO} systemctl list-unit-files blocky.service >/dev/null 2>&1; then
  ${SUDO} systemctl enable --now blocky.service
else
  echo "blocky.service not found; install package first" >&2
fi

# Ensure system resolver points to Blocky.
${SUDO} rm -f /etc/resolv.conf
printf "nameserver 127.0.0.1\nnameserver ::1\n" | ${SUDO} tee /etc/resolv.conf >/dev/null

# Prevent NetworkManager from overwriting resolv.conf.
if command -v nmcli >/dev/null 2>&1; then
  ${SUDO} install -d -m 755 "${NM_CONF_DIR}"
  ${SUDO} tee "${NM_CONF_DST}" >/dev/null <<'NMCONF'
[main]
dns=none
rc-manager=unmanaged
NMCONF
fi
