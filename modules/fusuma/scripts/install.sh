#!/usr/bin/env bash
set -euo pipefail

module_root="$(cd "$(dirname "$0")/.." && pwd)"
bin_dir="$HOME/.local/bin"

mkdir -p "$bin_dir"

for name in fusuma-workspace-monitor fusuma-hyprscrolling-focus fusuma-fullscreen fusuma-overview; do
  chmod +x "$module_root/scripts/$name" || true
  ln -sf "$module_root/scripts/$name" "$bin_dir/$name"
done

if command -v systemctl >/dev/null 2>&1; then
  systemctl --user daemon-reload >/dev/null 2>&1 || true
  systemctl --user enable --now fusuma.service >/dev/null 2>&1 || true
fi
