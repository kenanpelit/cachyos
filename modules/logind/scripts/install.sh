#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/../.." && pwd)"

SRC="${REPO_ROOT}/modules/logind/dotfiles/10-lid.conf"
DST_DIR="/etc/systemd/logind.conf.d"
DST="${DST_DIR}/10-lid.conf"

SUDO=""
if [ "$(id -u)" -ne 0 ]; then
  if ! command -v sudo >/dev/null 2>&1; then
    echo "sudo is required to install ${DST}" >&2
    exit 1
  fi
  SUDO="sudo"
fi

${SUDO} mkdir -p "${DST_DIR}"
${SUDO} install -m 644 "${SRC}" "${DST}"
