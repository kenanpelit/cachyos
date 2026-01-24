#!/usr/bin/env bash
set -euo pipefail

# --- User Config Setup ---
REAL_USER="${SUDO_USER:-$(whoami)}"
USER_HOME="$(getent passwd "$REAL_USER" | cut -d: -f6 2>/dev/null || true)"
if [ -z "${USER_HOME:-}" ]; then
  USER_HOME="$(eval echo "~$REAL_USER")"
fi

HYPR_DIR="$USER_HOME/.config/hypr"
DMS_DIR="$HYPR_DIR/dms"
BIN_DIR="$USER_HOME/.local/bin"

USER_GROUP=""
if [ "$(id -u)" -eq 0 ]; then
  USER_GROUP="$(id -gn "$REAL_USER" 2>/dev/null || true)"
fi

if [ "$(id -u)" -eq 0 ] && [ -n "$USER_GROUP" ]; then
  install -d -m0755 -o "$REAL_USER" -g "$USER_GROUP" "$HYPR_DIR" "$DMS_DIR" "$BIN_DIR"
  chown "$REAL_USER:$USER_GROUP" "$HYPR_DIR" "$DMS_DIR" "$BIN_DIR" 2>/dev/null || true
else
  mkdir -p "$DMS_DIR" "$BIN_DIR"
fi

for f in outputs.conf cursor.conf; do
  path="$DMS_DIR/$f"
  if [ -L "$path" ]; then
    rm -f "$path"
  fi
  if [ ! -e "$path" ]; then
    if [ "$(id -u)" -eq 0 ] && [ -n "$USER_GROUP" ]; then
      install -m0644 -o "$REAL_USER" -g "$USER_GROUP" /dev/null "$path"
    else
      : > "$path"
    fi
  fi
  chmod 0644 "$path" || true
  if [ "$(id -u)" -eq 0 ] && [ -n "$USER_GROUP" ]; then
    chown "$REAL_USER:$USER_GROUP" "$path" 2>/dev/null || true
  fi
done

# --- System-wide Session Entry ---
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
DOTFILES_DIR="$SCRIPT_DIR/../dotfiles"
# Desktop entry still needs to be in /usr/share/wayland-sessions to be seen by the greeter.
echo "Checking system-wide Hyprland session entry..."
if [ -w "/usr/share/wayland-sessions" ] || [ -n "${SUDO_USER:-}" ]; then
    mkdir -p "/usr/share/wayland-sessions"
    cp "$DOTFILES_DIR/hyprland-optimized.desktop" "/usr/share/wayland-sessions/hyprland-optimized.desktop"
    chmod 644 "/usr/share/wayland-sessions/hyprland-optimized.desktop"
else
    echo "  ! Skipping desktop entry install: No write access to /usr/share/wayland-sessions (run 'dcli sync' with sudo)"
fi
