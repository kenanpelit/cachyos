#!/usr/bin/env bash
set -euo pipefail

module_root="$(cd "$(dirname "$0")/.." && pwd)"
scripts_dir="$module_root/scripts"
start_dir="$module_root/../scripts/start"
bin_dir="$HOME/.local/bin"

mkdir -p "$bin_dir" "$HOME/.config/chrome-launcher"

# The chrome module owns profile_chrome (mirrors how modules/brave owns
# profile_brave). Symlinked so edits to the repo source are live, no reinstall.
ln -sf "$scripts_dir/profile_chrome.sh" "$bin_dir/profile_chrome" # isolated-profile engine
ln -sf "$scripts_dir/chromectl.sh"      "$bin_dir/chromectl"      # management dispatcher (kill/clean/ext/list)

# Generated per-profile launchers (start-chrome-*) live in the scripts module
# (Semsumo writes them there). Link whatever currently exists.
if [[ -d "$start_dir" ]]; then
	for f in "$start_dir"/start-chrome-*.sh; do
		[[ -e "$f" ]] || continue
		ln -sf "$f" "$bin_dir/$(basename "${f%.sh}")"
	done
fi

# Ensure a writable log file exists for profile_chrome
: >"$HOME/.config/chrome-launcher/chrome-launcher.log" 2>/dev/null || true
chmod u+rw "$HOME/.config/chrome-launcher/chrome-launcher.log" 2>/dev/null || true
