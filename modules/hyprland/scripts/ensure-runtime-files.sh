#!/usr/bin/env bash
set -euo pipefail

# --- User Config Setup ---
mkdir -p "$HOME/.config/hypr/dms"
mkdir -p "$HOME/.local/bin"

for f in outputs.conf cursor.conf; do
  path="$HOME/.config/hypr/dms/$f"
  if [ -L "$path" ]; then
    rm -f "$path"
  fi
  if [ ! -e "$path" ]; then
    : > "$path"
  fi
  chmod 0644 "$path" || true
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
