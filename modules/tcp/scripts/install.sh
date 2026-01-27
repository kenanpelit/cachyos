#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
SRC="${SCRIPT_DIR}/../dotfiles/99-tcp.conf"
DST_DIR="/etc/sysctl.d"
DST="${DST_DIR}/99-tcp.conf"

SUDO=""
if [ "$(id -u)" -ne 0 ]; then
  if ! command -v sudo >/dev/null 2>&1; then
    echo "sudo is required" >&2
    exit 1
  fi
  SUDO="sudo"
fi

${SUDO} install -m 644 "${SRC}" "${DST}"
${SUDO} sysctl --system >/dev/null 2>&1 || true
