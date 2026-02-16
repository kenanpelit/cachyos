#!/usr/bin/env bash
set -euo pipefail

# Manual installer for host "hay" only.
# Usage:
#   sudo bash modules/grub/scripts/install-hay.sh
#
# Optional overrides:
#   OSC_GRUB_HAY_ROOT_UUID=...
#   OSC_GRUB_HAY_ESP_UUID=...

if [ "$EUID" -ne 0 ]; then
    echo "Please run as root."
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE="${SCRIPT_DIR}/../dotfiles/40_custom.hay"
TARGET="/etc/grub.d/40_custom"
ROOT_UUID="${OSC_GRUB_HAY_ROOT_UUID:-4c9b9c8a-398c-41f4-97a7-3ae12196f129}"
ESP_UUID="${OSC_GRUB_HAY_ESP_UUID:-0BAC-3F29}"

if [ ! -f "$TEMPLATE" ]; then
    echo "Template not found: $TEMPLATE" >&2
    exit 1
fi

tmp="$(mktemp)"
cleanup() {
    rm -f "$tmp"
}
trap cleanup EXIT

sed \
    -e "s/4c9b9c8a-398c-41f4-97a7-3ae12196f129/${ROOT_UUID}/g" \
    -e "s/0BAC-3F29/${ESP_UUID}/g" \
    "$TEMPLATE" >"$tmp"

install -m 755 "$tmp" "$TARGET"

echo "Updating GRUB configuration..."
if command -v update-grub >/dev/null 2>&1; then
    update-grub
else
    grub-mkconfig -o /boot/grub/grub.cfg
fi

echo "Done. Installed machine-specific 40_custom for hay."
