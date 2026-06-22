#!/usr/bin/env bash
set -euo pipefail

module_root="$(cd "$(dirname "$0")/.." && pwd)"
scripts_dir="$module_root/scripts"
bin_dir="$HOME/.local/bin"

mkdir -p "$bin_dir" "$HOME/.config/brave-launcher"

# The brave module owns every brave bin (mirrors how modules/helium owns
# profile_helium). Symlinked so edits to the repo sources are live, no reinstall.
ln -sf "$scripts_dir/brave-launcher"   "$bin_dir/brave"          # browser wrapper (shadows system brave)
ln -sf "$scripts_dir/profile_brave.sh" "$bin_dir/profile_brave"  # isolated-profile engine
ln -sf "$scripts_dir/bravectl.sh"      "$bin_dir/bravectl"       # management dispatcher

# Drop the old redundant brave-launcher twin if a previous install left it.
rm -f "$bin_dir/brave-launcher"

# Ensure writable log file exists for profile_brave
: >"$HOME/.config/brave-launcher/brave-launcher.log" 2>/dev/null || true
chmod u+rw "$HOME/.config/brave-launcher/brave-launcher.log" 2>/dev/null || true
