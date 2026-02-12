#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
WRAPPER_SRC="${SCRIPT_DIR}/../dotfiles/bin/pacman-sudo-paru"

REAL_USER="${SUDO_USER:-$(whoami)}"
USER_HOME="$(getent passwd "$REAL_USER" | cut -d: -f6 2>/dev/null || true)"
if [ -z "${USER_HOME:-}" ]; then
  USER_HOME="$(eval echo "~$REAL_USER")"
fi

BIN_DIR="${USER_HOME}/.local/bin"
WRAPPER_DST="${BIN_DIR}/pacman-sudo-paru"

if [ "$(id -u)" -eq 0 ]; then
  USER_GROUP="$(id -gn "$REAL_USER" 2>/dev/null || true)"
  install -d -m 755 -o "$REAL_USER" -g "${USER_GROUP:-$REAL_USER}" "$BIN_DIR"
  install -m 755 -o "$REAL_USER" -g "${USER_GROUP:-$REAL_USER}" "$WRAPPER_SRC" "$WRAPPER_DST"
else
  install -d -m 755 "$BIN_DIR"
  install -m 755 "$WRAPPER_SRC" "$WRAPPER_DST"
fi
