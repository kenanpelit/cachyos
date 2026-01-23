#!/usr/bin/env bash
set -e

# This script requires root to update system GRUB
if [ "$EUID" -ne 0 ]; then
    echo "Please run as root (via dcli sync with sudo)"
    exit 1
fi

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
CUSTOM_FILE="$SCRIPT_DIR/../dotfiles/40_custom"

echo "Installing custom GRUB entry..."
cp "$CUSTOM_FILE" /etc/grub.d/40_custom
chmod +x /etc/grub.d/40_custom

echo "Updating GRUB configuration..."
if command -v update-grub >/dev/null 2>&1; then
    update-grub
else
    grub-mkconfig -o /boot/grub/grub.cfg
fi

echo "GRUB update complete."
