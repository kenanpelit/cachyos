#!/usr/bin/env bash
set -euo pipefail

SUDO=""
if [ "$(id -u)" -ne 0 ]; then
  if ! command -v sudo >/dev/null 2>&1; then
    echo "sudo is required to install wayland-env" >&2
    exit 1
  fi
  SUDO="sudo"
fi

run_root() {
  if [ -n "${SUDO}" ]; then
    "${SUDO}" "$@"
  else
    "$@"
  fi
}

ENV_DST="/etc/environment"
TMP="$(mktemp)"
MANAGED_BEGIN="# >>> mdots-wayland-env >>>"
MANAGED_END="# <<< mdots-wayland-env <<<"

cleanup() {
  rm -f "${TMP}" "${TMP}.new"
}
trap cleanup EXIT

if ! run_root test -f "${ENV_DST}"; then
  run_root install -m 644 /dev/null "${ENV_DST}"
fi

run_root awk -v begin="${MANAGED_BEGIN}" -v end="${MANAGED_END}" '
  $0 == begin { skip=1; next }
  $0 == end { skip=0; next }
  !skip { print }
' "${ENV_DST}" >"${TMP}"

{
  cat "${TMP}"
  printf '\n%s\n' "${MANAGED_BEGIN}"
  printf 'XCURSOR_THEME=capitaine-cursors\n'
  printf 'XCURSOR_SIZE=24\n'
  printf '%s\n' "${MANAGED_END}"
} >"${TMP}.new"

if run_root cmp -s "${TMP}.new" "${ENV_DST}"; then
  exit 0
fi

run_root install -m 644 "${TMP}.new" "${ENV_DST}"
