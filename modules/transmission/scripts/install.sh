#!/usr/bin/env bash
set -euo pipefail

module_root="$(cd "$(dirname "$0")/.." && pwd)"
bin_dir="$HOME/.local/bin"

mkdir -p "$bin_dir"
ln -sf "$module_root/scripts/transmission-setup" "$bin_dir/transmission-setup"

if command -v systemctl >/dev/null 2>&1; then
  systemctl --user daemon-reload >/dev/null 2>&1 || true
  systemctl --user enable --now transmission.timer >/dev/null 2>&1 || true
fi
