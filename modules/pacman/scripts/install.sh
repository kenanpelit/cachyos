#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
SRC="${SCRIPT_DIR}/../dotfiles/pacman.conf"
DST="/etc/pacman.conf"

if [ ! -f "${SRC}" ]; then
  echo "pacman.conf not found at ${SRC}" >&2
  exit 1
fi

SUDO=""
if [ "$(id -u)" -ne 0 ]; then
  if ! command -v sudo >/dev/null 2>&1; then
    echo "sudo is required to install ${DST}" >&2
    exit 1
  fi
  SUDO="sudo"
fi

if [ -L "${DST}" ] || { [ -e "${DST}" ] && [ ! -f "${DST}" ]; }; then
  ${SUDO} rm -f "${DST}"
fi

if [ -f "${DST}" ] && cmp -s "${SRC}" "${DST}"; then
  exit 0
fi

${SUDO} install -m 644 "${SRC}" "${DST}"
