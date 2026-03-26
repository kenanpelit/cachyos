#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ISSUE_SRC="${SCRIPT_DIR}/../dotfiles/issue"
ISSUE_DST="/etc/issue"
VCONSOLE_DST="/etc/vconsole.conf"
TARGET_FONT="${TTY_FONT:-ter-v22n}"
TARGET_KEYMAP="${TTY_KEYMAP:-}"

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

infer_vconsole_keymap() {
  local current_layout=""
  local current_variant=""

  if [ -n "${TARGET_KEYMAP}" ]; then
    printf '%s\n' "${TARGET_KEYMAP}"
    return 0
  fi

  [ -f "${VCONSOLE_DST}" ] || return 1

  current_layout="$(awk -F= '/^XKBLAYOUT=/{print $2; exit}' "${VCONSOLE_DST}" 2>/dev/null || true)"
  current_variant="$(awk -F= '/^XKBVARIANT=/{print $2; exit}' "${VCONSOLE_DST}" 2>/dev/null || true)"

  case "${current_layout}:${current_variant}" in
    tr:f)
      printf 'trf\n'
      return 0
      ;;
    tr:q | tr:)
      printf 'trq\n'
      return 0
      ;;
  esac

  return 1
}

set_vconsole_settings() {
  local tmp
  local target_keymap=""
  tmp="$(mktemp)"
  target_keymap="$(infer_vconsole_keymap 2>/dev/null || true)"

  if [ -f "${VCONSOLE_DST}" ]; then
    awk -v font="${TARGET_FONT}" -v keymap="${target_keymap}" '
      BEGIN { has_font = 0; has_keymap = 0 }
      /^FONT=/ {
        print "FONT=" font
        has_font = 1
        next
      }
      /^KEYMAP=/ {
        if (keymap != "") {
          print "KEYMAP=" keymap
        } else {
          print
        }
        has_keymap = 1
        next
      }
      { print }
      END {
        if (!has_font) {
          print "FONT=" font
        }
        if (keymap != "" && !has_keymap) {
          print "KEYMAP=" keymap
        }
      }
    ' "${VCONSOLE_DST}" >"${tmp}"
  else
    printf 'FONT=%s\n' "${TARGET_FONT}" >"${tmp}"
    if [ -n "${target_keymap}" ]; then
      printf 'KEYMAP=%s\n' "${target_keymap}" >>"${tmp}"
    fi
  fi

  if [ ! -f "${VCONSOLE_DST}" ] || ! cmp -s "${tmp}" "${VCONSOLE_DST}"; then
    ${SUDO} install -m 644 "${tmp}" "${VCONSOLE_DST}"
  fi

  rm -f "${tmp}"
}

install_if_changed "${ISSUE_SRC}" "${ISSUE_DST}" 644
set_vconsole_settings

# Best-effort immediate apply for current boot; next boot/login guarantees apply.
if command -v setfont >/dev/null 2>&1; then
  ${SUDO} setfont "${TARGET_FONT}" >/dev/null 2>&1 || true
fi

if target_keymap="$(infer_vconsole_keymap 2>/dev/null || true)" && [ -n "${target_keymap}" ]; then
  if command -v loadkeys >/dev/null 2>&1; then
    ${SUDO} loadkeys "${target_keymap}" >/dev/null 2>&1 || true
  fi
fi

${SUDO} systemctl restart systemd-vconsole-setup.service >/dev/null 2>&1 || true
