#!/usr/bin/env bash
set -e

# This script installs the optimized .desktop files to /usr/share/wayland-sessions/
# It requires root privileges.

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
DOTFILES_DIR="$SCRIPT_DIR/../dotfiles"
HYPR_DOTFILES_DIR="$SCRIPT_DIR/../../hyprland/dotfiles"

DEST_DIR="/usr/share/wayland-sessions"

install_session() {
    local src="$1"
    local name="$2"
    if [ -f "$src" ]; then
        echo "Installing $name to $DEST_DIR..."
        sudo mkdir -p "$DEST_DIR"
        sudo cp "$src" "$DEST_DIR/"
        sudo chmod 644 "$DEST_DIR/$(basename "$src")"
    else
        echo "Warning: $src not found, skipping $name."
    fi
}

remove_session() {
    local name="$1"
    local target="$DEST_DIR/$name"
    if [ -e "$target" ] || [ -L "$target" ]; then
        echo "Removing legacy session $target..."
        sudo rm -f "$target"
    fi
}

# Keep Niri on a single UWSM-owned session entry.
remove_session "niri.desktop"
remove_session "niri-optimized.desktop"
install_session "$DOTFILES_DIR/niri-uwsm.desktop" "Niri (UWSM)"

# Install GNOME
install_session "$DOTFILES_DIR/gnome-optimized.desktop" "GNOME (Optimized)"

# Keep Hyprland on the single UWSM-backed session entry.
remove_session "hyprland.desktop"
install_session "$HYPR_DOTFILES_DIR/hyprland-uwsm.desktop" "Hyprland (UWSM)"

echo "Session installation complete."
