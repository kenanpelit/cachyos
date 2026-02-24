#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ISSUE_SRC="${SCRIPT_DIR}/../dotfiles/issue"
ISSUE_DST="/etc/issue"
VCONSOLE_DST="/etc/vconsole.conf"
TARGET_FONT="${TTY_FONT:-ter-v22n}"

SUDO=""
if [ "$(id -u)" -ne 0 ]; then
  if ! command -v sudo >/dev/null 2>&1; then
    echo "sudo is required to install tty settings" >&2
    exit 1
  fi
  SUDO="sudo"
fi

install_if_changed() {
  local src="$1"
  local dst="$2"
  local mode="$3"

  if [ -L "${dst}" ] || { [ -e "${dst}" ] && [ ! -f "${dst}" ]; }; then
    ${SUDO} rm -f "${dst}"
  fi

  if [ -f "${dst}" ] && cmp -s "${src}" "${dst}"; then
    return 0
  fi

  ${SUDO} install -m "${mode}" "${src}" "${dst}"
}

set_vconsole_font() {
  local tmp
  tmp="$(mktemp)"

  if [ -f "${VCONSOLE_DST}" ]; then
    awk -v font="${TARGET_FONT}" '
      BEGIN { has_font = 0 }
      /^FONT=/ {
        print "FONT=" font
        has_font = 1
        next
      }
      { print }
      END {
        if (!has_font) {
          print "FONT=" font
        }
      }
    ' "${VCONSOLE_DST}" >"${tmp}"
  else
    printf 'FONT=%s\n' "${TARGET_FONT}" >"${tmp}"
  fi

  if [ ! -f "${VCONSOLE_DST}" ] || ! cmp -s "${tmp}" "${VCONSOLE_DST}"; then
    ${SUDO} install -m 644 "${tmp}" "${VCONSOLE_DST}"
  fi

  rm -f "${tmp}"
}

install_if_changed "${ISSUE_SRC}" "${ISSUE_DST}" 644
set_vconsole_font

# Best-effort immediate apply for current boot; next boot/login guarantees apply.
if command -v setfont >/dev/null 2>&1; then
  ${SUDO} setfont "${TARGET_FONT}" >/dev/null 2>&1 || true
fi

${SUDO} systemctl restart systemd-vconsole-setup.service >/dev/null 2>&1 || true
