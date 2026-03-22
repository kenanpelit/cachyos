#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
CONF_SRC="${SCRIPT_DIR}/../dotfiles/ufw.conf"
DEFAULT_SRC="${SCRIPT_DIR}/../dotfiles/default-ufw"
ENV_SRC="${SCRIPT_DIR}/../dotfiles/firewall.env"

CONF_DST="/etc/ufw/ufw.conf"
DEFAULT_DST="/etc/default/ufw"
ENV_DST="/etc/ufw/firewall.env"

SUDO=""
if [ "$(id -u)" -ne 0 ]; then
  if ! command -v sudo >/dev/null 2>&1; then
    echo "sudo is required" >&2
    exit 1
  fi
  SUDO="sudo"
fi

${SUDO} install -m 644 "${CONF_SRC}" "${CONF_DST}"
${SUDO} install -m 644 "${DEFAULT_SRC}" "${DEFAULT_DST}"
${SUDO} install -m 644 "${ENV_SRC}" "${ENV_DST}"

# Apply rules
# shellcheck source=/etc/ufw/firewall.env
set +u
. "${ENV_DST}"
set -u

SSH_PORT="${SSH_PORT:-22}"
ALLOW_TRANSMISSION_PORTS="${ALLOW_TRANSMISSION_PORTS:-0}"
ALLOW_CUSTOM_SERVICE_PORT="${ALLOW_CUSTOM_SERVICE_PORT:-0}"
CUSTOM_SERVICE_PORT="${CUSTOM_SERVICE_PORT:-1401}"
TRANSMISSION_WEB_PORT="${TRANSMISSION_WEB_PORT:-9091}"
TRANSMISSION_PEER_PORT="${TRANSMISSION_PEER_PORT:-51413}"
ALLOW_KDECONNECT_PORTS="${ALLOW_KDECONNECT_PORTS:-0}"
KDECONNECT_PORT_RANGE="${KDECONNECT_PORT_RANGE:-1714:1764}"
KDECONNECT_ALLOWED_SUBNETS="${KDECONNECT_ALLOWED_SUBNETS:-}"
ALLOW_MDNS_PORT="${ALLOW_MDNS_PORT:-0}"
MDNS_PORT="${MDNS_PORT:-5353}"

if command -v ufw >/dev/null 2>&1; then
  ${SUDO} ufw --force reset
  ${SUDO} ufw default deny incoming
  ${SUDO} ufw default allow outgoing
  ${SUDO} ufw allow "${SSH_PORT}/tcp"

  # Allow mDNS for local discovery (Avahi/KDE Connect)
  ${SUDO} ufw allow 5353/udp

  if [ "${ALLOW_TRANSMISSION_PORTS}" = "1" ]; then
    ${SUDO} ufw allow "${TRANSMISSION_WEB_PORT}/tcp"
    ${SUDO} ufw allow "${TRANSMISSION_PEER_PORT}/udp"
  fi

  if [ "${ALLOW_CUSTOM_SERVICE_PORT}" = "1" ]; then
    ${SUDO} ufw allow "${CUSTOM_SERVICE_PORT}/tcp"
  fi

  if [ "${ALLOW_KDECONNECT_PORTS}" = "1" ]; then
    if [ -n "${KDECONNECT_ALLOWED_SUBNETS// /}" ]; then
      # Accept comma and/or whitespace separated subnet list.
      IFS=', ' read -r -a kde_subnets <<< "${KDECONNECT_ALLOWED_SUBNETS}"
      for subnet in "${kde_subnets[@]}"; do
        [ -n "${subnet}" ] || continue
        ${SUDO} ufw allow from "${subnet}" to any port "${KDECONNECT_PORT_RANGE}" proto udp
        ${SUDO} ufw allow from "${subnet}" to any port "${KDECONNECT_PORT_RANGE}" proto tcp
      done
    else
      ${SUDO} ufw allow "${KDECONNECT_PORT_RANGE}/udp"
      ${SUDO} ufw allow "${KDECONNECT_PORT_RANGE}/tcp"
    fi
  fi

  ${SUDO} ufw --force enable
fi
