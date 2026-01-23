#!/usr/bin/env bash
set -euo pipefail

module_root="$(cd "$(dirname "$0")/.." && pwd)"
bin_dir="$HOME/.local/bin"

mkdir -p "$bin_dir" "$HOME/.config/chrome-launcher"

ln -sf "$module_root/scripts/chrome-launcher" "$bin_dir/chrome-launcher"

# Ensure writable log file exists for profile_chrome.sh
: >"$HOME/.config/chrome-launcher/chrome-launcher.log" 2>/dev/null || true
chmod u+rw "$HOME/.config/chrome-launcher/chrome-launcher.log" 2>/dev/null || true
