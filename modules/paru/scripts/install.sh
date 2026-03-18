#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

REAL_USER="${SUDO_USER:-$(whoami)}"
USER_HOME="$(getent passwd "$REAL_USER" | cut -d: -f6 2>/dev/null || true)"
if [ -z "${USER_HOME:-}" ]; then
  USER_HOME="$(eval echo "~$REAL_USER")"
fi

BIN_DIR="${USER_HOME}/.local/bin"
WRAPPER_DST="${BIN_DIR}/pacman-sudo-paru"
PARU_DIR="${USER_HOME}/.config/paru"
PARU_CONF="${PARU_DIR}/paru.conf"
PARU_CONF_CONTENT="# See paru.conf(5)
[bin]
Sudo = /usr/bin/sudo
Pacman = ${WRAPPER_DST}
"

write_paru_conf() {
  if [ -f "$PARU_CONF" ] && [ "$(cat "$PARU_CONF")" = "$PARU_CONF_CONTENT" ]; then
    return 0
  fi

  printf "%s" "$PARU_CONF_CONTENT" >"$PARU_CONF"
}

if [ "$(id -u)" -eq 0 ]; then
  USER_GROUP="$(id -gn "$REAL_USER" 2>/dev/null || true)"
  install -d -m 755 -o "$REAL_USER" -g "${USER_GROUP:-$REAL_USER}" "$BIN_DIR"
  install -d -m 755 -o "$REAL_USER" -g "${USER_GROUP:-$REAL_USER}" "$PARU_DIR"
  write_paru_conf
  chown "$REAL_USER:${USER_GROUP:-$REAL_USER}" "$PARU_CONF"
  chmod 644 "$PARU_CONF"
else
  install -d -m 755 "$BIN_DIR"
  install -d -m 755 "$PARU_DIR"
  write_paru_conf
  chmod 644 "$PARU_CONF"
fi
