#!/usr/bin/env bash
set -euo pipefail

module_root="$(cd "$(dirname "$0")/.." && pwd)"
bin_dir="$HOME/.local/bin"
flathub_url="https://flathub.org/repo/flathub.flatpakrepo"

mkdir -p "$bin_dir" "$HOME/.config/flatpak"
chmod +x "$module_root/scripts/flatpak-managed-install" || true
ln -sf "$module_root/scripts/flatpak-managed-install" "$bin_dir/flatpak-managed-install"

# Ensure flathub remote exists early (before timer-driven installs).
if command -v flatpak >/dev/null 2>&1; then
  if ! flatpak remotes --user --columns=name 2>/dev/null | awk '{print $1}' | grep -qx flathub; then
    flatpak remote-add --user --if-not-exists flathub "$flathub_url" >/dev/null 2>&1 || true
  fi
fi

if command -v systemctl >/dev/null 2>&1; then
  systemctl --user daemon-reload >/dev/null 2>&1 || true
  systemctl --user stop flatpak-managed-install.service >/dev/null 2>&1 || true
  systemctl --user reset-failed flatpak-managed-install.service >/dev/null 2>&1 || true
  systemctl --user enable --now flatpak-managed-install.timer >/dev/null 2>&1 || true
fi
