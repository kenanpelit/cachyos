#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
CFG_SRC="${SCRIPT_DIR}/../dotfiles/blocky/config.yml"
CFG_DST="/etc/blocky/blocky.yml"
OVERRIDE_DIR="/etc/systemd/system/blocky.service.d"
OVERRIDE_DST="${OVERRIDE_DIR}/override.conf"
NM_CONF_DIR="/etc/NetworkManager/conf.d"
NM_CONF_DST="${NM_CONF_DIR}/90-blocky-dns.conf"
ENSURE_SRC="${SCRIPT_DIR}/../dotfiles/libexec/osc-mullvad-boot-ensure"
ENSURE_DST="/usr/local/libexec/osc-mullvad-boot-ensure"
ENSURE_UNIT_SRC="${SCRIPT_DIR}/../dotfiles/systemd/system/osc-mullvad-boot-ensure.service"
ENSURE_UNIT_DST="/etc/systemd/system/osc-mullvad-boot-ensure.service"
ENSURE_UNIT_NAME="osc-mullvad-boot-ensure.service"

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

if ${SUDO} systemctl list-unit-files blocky.service >/dev/null 2>&1; then
  # Blocky autostart is managed by osc-mullvad-boot-ensure.
  ${SUDO} systemctl disable blocky.service >/dev/null 2>&1 || true
else
  echo "blocky.service not found; install package first" >&2
fi

${SUDO} install -d -m 755 "$(dirname "${ENSURE_DST}")"
${SUDO} install -m 755 "${ENSURE_SRC}" "${ENSURE_DST}"
${SUDO} install -d -m 755 "$(dirname "${ENSURE_UNIT_DST}")"
${SUDO} install -m 644 "${ENSURE_UNIT_SRC}" "${ENSURE_UNIT_DST}"

# Prevent NetworkManager from overwriting resolv.conf.
if command -v nmcli >/dev/null 2>&1; then
  ${SUDO} install -d -m 755 "${NM_CONF_DIR}"
  ${SUDO} tee "${NM_CONF_DST}" >/dev/null <<'NMCONF'
[main]
dns=none
rc-manager=unmanaged
NMCONF
fi

${SUDO} systemctl daemon-reload
if ${SUDO} systemctl list-unit-files "${ENSURE_UNIT_NAME}" >/dev/null 2>&1; then
  # Run now to reconcile state immediately:
  # - Mullvad healthy => stop Blocky
  # - Mullvad disconnected/unhealthy => start Blocky + local resolver
  ${SUDO} systemctl enable --now "${ENSURE_UNIT_NAME}"
fi
