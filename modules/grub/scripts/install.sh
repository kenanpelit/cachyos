#!/usr/bin/env bash
set -euo pipefail

# This script requires root to update system GRUB
if [ "$EUID" -ne 0 ]; then
    echo "Please run as root (via dcli sync with sudo)"
    exit 1
fi

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
CUSTOM_FILE="$SCRIPT_DIR/../dotfiles/40_custom"
SECONDARY_ROOT="/cachy/@"
CURRENT_BOOT_GRUB="/boot/grub"
SECONDARY_BOOT_GRUB="$SECONDARY_ROOT/boot/grub"

install_custom_cfg() {
    local target_dir="$1"
    mkdir -p "$target_dir"
    tail -n +3 "$CUSTOM_FILE" > "$target_dir/custom.cfg"
}

echo "Installing custom GRUB entry..."
cp "$CUSTOM_FILE" /etc/grub.d/40_custom
chmod +x /etc/grub.d/40_custom

echo "Updating GRUB configuration..."
if command -v update-grub >/dev/null 2>&1; then
    update-grub
else
    grub-mkconfig -o /boot/grub/grub.cfg
fi
install_custom_cfg "$CURRENT_BOOT_GRUB"

if [ -d "$SECONDARY_ROOT/etc/grub.d" ]; then
    echo "Syncing custom GRUB entry to secondary CachyOS root: $SECONDARY_ROOT"
    cp "$CUSTOM_FILE" "$SECONDARY_ROOT/etc/grub.d/40_custom"
    chmod +x "$SECONDARY_ROOT/etc/grub.d/40_custom"
    install_custom_cfg "$SECONDARY_BOOT_GRUB"
    echo "Secondary custom.cfg synced: $SECONDARY_BOOT_GRUB/custom.cfg"
fi

echo "GRUB update complete."
