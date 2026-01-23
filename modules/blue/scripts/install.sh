#!/usr/bin/env bash
set -euo pipefail

module_root="$(cd "$(dirname "$0")/.." && pwd)"
bin_dir="$HOME/.local/bin"

mkdir -p "$bin_dir"
ln -sf "$module_root/scripts/hypr-blue-manager" "$bin_dir/hypr-blue-manager"

if command -v systemctl >/dev/null 2>&1; then
  systemctl --user daemon-reload >/dev/null 2>&1 || true
  # Enable on request; this module can conflict with sunsetr.
  systemctl --user enable --now blue.service >/dev/null 2>&1 || true
fi
