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

# Install Niri
install_session "$DOTFILES_DIR/niri-optimized.desktop" "Niri (Optimized)"

# Install GNOME
install_session "$DOTFILES_DIR/gnome-optimized.desktop" "GNOME (Optimized)"

# Install Hyprland (from its module)
install_session "$HYPR_DOTFILES_DIR/hyprland-optimized.desktop" "Hyprland (Optimized)"

echo "Session installation complete."
