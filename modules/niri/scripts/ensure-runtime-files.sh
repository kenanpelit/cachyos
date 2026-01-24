#!/usr/bin/env bash
set -euo pipefail

REAL_USER="${SUDO_USER:-$(whoami)}"
USER_HOME="$(getent passwd "$REAL_USER" | cut -d: -f6 2>/dev/null || true)"
if [ -z "${USER_HOME:-}" ]; then
  USER_HOME="$(eval echo "~$REAL_USER")"
fi

DMS_DIR="$USER_HOME/.config/niri/dms"
USER_GROUP=""
if [ "$(id -u)" -eq 0 ]; then
  USER_GROUP="$(id -gn "$REAL_USER" 2>/dev/null || true)"
fi

if [ "$(id -u)" -eq 0 ] && [ -n "$USER_GROUP" ]; then
  install -d -m0755 -o "$REAL_USER" -g "$USER_GROUP" "$DMS_DIR"
else
  mkdir -p "$DMS_DIR"
fi

for f in outputs.kdl zen.kdl cursor.kdl alttab.kdl layout.kdl; do
  path="$DMS_DIR/$f"
  # If it's a broken symlink or doesn't exist, create it
  if [ ! -e "$path" ]; then
    echo "Creating empty runtime file: $path"
    if [ "$(id -u)" -eq 0 ] && [ -n "$USER_GROUP" ]; then
      install -m0644 -o "$REAL_USER" -g "$USER_GROUP" /dev/null "$path"
    else
      : > "$path"
    fi
  fi
  chmod 0644 "$path" || true
done
