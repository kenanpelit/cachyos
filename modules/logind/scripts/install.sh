#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
SUDO=""
if [ "$(id -u)" -ne 0 ]; then
  if ! command -v sudo >/dev/null 2>&1; then
    echo "sudo is required to install ${DST}" >&2
    exit 1
  fi
  SUDO="sudo"
fi

SRC="${SCRIPT_DIR}/../dotfiles/10-lid.conf"
DST_DIR="/etc/systemd/logind.conf.d"
DST="${DST_DIR}/10-lid.conf"
SLEEP_SRC="${SCRIPT_DIR}/../dotfiles/system-sleep/00-lock-before-sleep"
SLEEP_DST_DIR="/etc/systemd/system-sleep"
SLEEP_DST="${SLEEP_DST_DIR}/00-lock-before-sleep"

if [ -L "${DST}" ] || { [ -e "${DST}" ] && [ ! -f "${DST}" ]; }; then
  ${SUDO} rm -f "${DST}"
fi

if [ -L "${SLEEP_DST}" ] || { [ -e "${SLEEP_DST}" ] && [ ! -f "${SLEEP_DST}" ]; }; then
  ${SUDO} rm -f "${SLEEP_DST}"
fi

needs_install=0
if [ ! -f "${DST}" ] || ! cmp -s "${SRC}" "${DST}"; then
  needs_install=1
fi
if [ ! -f "${SLEEP_DST}" ] || ! cmp -s "${SLEEP_SRC}" "${SLEEP_DST}"; then
  needs_install=1
fi

if [ "${needs_install}" -eq 0 ]; then
  exit 0
fi

${SUDO} mkdir -p "${DST_DIR}"
${SUDO} install -m 644 "${SRC}" "${DST}"
${SUDO} mkdir -p "${SLEEP_DST_DIR}"
${SUDO} install -m 755 "${SLEEP_SRC}" "${SLEEP_DST}"
