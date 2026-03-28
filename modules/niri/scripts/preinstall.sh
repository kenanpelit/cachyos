#!/usr/bin/env bash
set -euo pipefail

SUDO=""

if [ "$(id -u)" -ne 0 ]; then
  if ! command -v sudo >/dev/null 2>&1; then
    echo "sudo is required" >&2
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

# niri-git conflicts with the distro stable/binary variants. Remove them before
# the module package batch starts so dcli can keep running non-interactively.
if command -v pacman >/dev/null 2>&1; then
  for pkg in niri niri-bin; do
    if pacman -Qq "$pkg" >/dev/null 2>&1; then
      run_root pacman -Rns --noconfirm "$pkg"
    fi
  done
fi
