#!/usr/bin/env bash
set -euo pipefail

module_root="$(cd "$(dirname "$0")/.." && pwd)"
bin_dir="$HOME/.local/bin"

mkdir -p "$bin_dir" "$HOME/.config/flatpak"
ln -sf "$module_root/scripts/flatpak-managed-install" "$bin_dir/flatpak-managed-install"

if command -v systemctl >/dev/null 2>&1; then
  systemctl --user daemon-reload >/dev/null 2>&1 || true
  systemctl --user enable --now flatpak-managed-install.timer >/dev/null 2>&1 || true
fi
