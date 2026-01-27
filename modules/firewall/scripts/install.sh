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

if command -v ufw >/dev/null 2>&1; then
  ${SUDO} ufw --force reset
  ${SUDO} ufw default deny incoming
  ${SUDO} ufw default allow outgoing
  ${SUDO} ufw allow "${SSH_PORT}/tcp"

  if [ "${ALLOW_TRANSMISSION_PORTS}" = "1" ]; then
    ${SUDO} ufw allow "${TRANSMISSION_WEB_PORT}/tcp"
    ${SUDO} ufw allow "${TRANSMISSION_PEER_PORT}/udp"
  fi

  if [ "${ALLOW_CUSTOM_SERVICE_PORT}" = "1" ]; then
    ${SUDO} ufw allow "${CUSTOM_SERVICE_PORT}/tcp"
  fi

  ${SUDO} ufw --force enable
fi
