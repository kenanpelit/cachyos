#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

WIRELESS_REGDOM_SRC="${SCRIPT_DIR}/../dotfiles/wireless-regdom"
WIRELESS_REGDOM_DST="/etc/conf.d/wireless-regdom"
IW_REGDOMAIN_SRC="${SCRIPT_DIR}/../dotfiles/iw-regdomain"
IW_REGDOMAIN_DST="/etc/iw-regdomain"

SUDO=""
if [ "$(id -u)" -ne 0 ]; then
  if ! command -v sudo >/dev/null 2>&1; then
    echo "sudo is required" >&2
    exit 1
  fi
  SUDO="sudo"
fi

CHANGED=0

install_managed_file() {
  local src="$1"
  local dst="$2"
  local mode="$3"

  if [ ! -f "${src}" ]; then
    echo "missing source file: ${src}" >&2
    exit 1
  fi

  if [ -L "${dst}" ] || { [ -e "${dst}" ] && [ ! -f "${dst}" ]; }; then
    ${SUDO} rm -f "${dst}"
  fi

  if [ -f "${dst}" ] && cmp -s "${src}" "${dst}"; then
    return 0
  fi

  ${SUDO} install -d -m 755 "$(dirname "${dst}")"
  ${SUDO} install -m "${mode}" "${src}" "${dst}"
  CHANGED=1
}

install_managed_file "${WIRELESS_REGDOM_SRC}" "${WIRELESS_REGDOM_DST}" 644
install_managed_file "${IW_REGDOMAIN_SRC}" "${IW_REGDOMAIN_DST}" 644

if ${SUDO} systemctl list-unit-files cachyos-iw-set-regdomain.path >/dev/null 2>&1; then
  ${SUDO} systemctl enable --now cachyos-iw-set-regdomain.path >/dev/null 2>&1 || true
fi

if [ "${CHANGED}" -eq 1 ]; then
  if [ -x /usr/lib/iw-set-regdomain ]; then
    ${SUDO} /usr/lib/iw-set-regdomain >/dev/null 2>&1 || true
  elif command -v iw >/dev/null 2>&1; then
    ${SUDO} iw reg set TR >/dev/null 2>&1 || true
  fi
fi
