#!/usr/bin/env bash
set -euo pipefail

module_root="$(cd "$(dirname "$0")/.." && pwd)"
bin_dir="$HOME/.local/bin"
udev_src="$module_root/dotfiles/udev/90-fusuma.rules"
udev_dst="/etc/udev/rules.d/90-fusuma.rules"

mkdir -p "$bin_dir"

for name in fusuma-workspace-monitor fusuma-hyprscrolling-focus fusuma-fullscreen fusuma-overview; do
  chmod +x "$module_root/scripts/$name" || true
  ln -sf "$module_root/scripts/$name" "$bin_dir/$name"
done

SUDO=""
if [ "$(id -u)" -ne 0 ]; then
  if command -v sudo >/dev/null 2>&1; then
    SUDO="sudo"
  fi
fi

target_user="${SUDO_USER:-$USER}"
if [ -z "$target_user" ] || [ "$target_user" = "root" ]; then
  target_user="$(logname 2>/dev/null || true)"
fi

if [ -f "$udev_src" ] && [ -n "$SUDO" ]; then
  $SUDO install -m 644 "$udev_src" "$udev_dst"
  $SUDO groupadd -f input >/dev/null 2>&1 || true
  if [ -n "$target_user" ] && ! id -nG "$target_user" | tr ' ' '\n' | grep -q "^input$"; then
    $SUDO usermod -aG input "$target_user" || true
    echo "Added $target_user to input group. Re-login required for fusuma permissions."
  fi
  $SUDO udevadm control --reload-rules >/dev/null 2>&1 || true
  $SUDO udevadm trigger --subsystem-match=input >/dev/null 2>&1 || true
fi

if command -v systemctl >/dev/null 2>&1; then
  systemctl --user daemon-reload >/dev/null 2>&1 || true
  systemctl --user enable --now fusuma.service >/dev/null 2>&1 || true
fi
