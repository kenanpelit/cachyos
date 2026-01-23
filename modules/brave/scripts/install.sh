#!/usr/bin/env bash
set -euo pipefail

module_root="$(cd "$(dirname "$0")/.." && pwd)"
bin_dir="$HOME/.local/bin"

mkdir -p "$bin_dir" "$HOME/.config/brave-launcher"

ln -sf "$module_root/scripts/brave-launcher" "$bin_dir/brave-launcher"

# Ensure writable log file exists for profile_brave.sh
: >"$HOME/.config/brave-launcher/brave-launcher.log" 2>/dev/null || true
chmod u+rw "$HOME/.config/brave-launcher/brave-launcher.log" 2>/dev/null || true
