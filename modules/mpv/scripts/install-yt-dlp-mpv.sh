#!/usr/bin/env bash
set -euo pipefail

module_root="$(cd "$(dirname "$0")/.." && pwd)"
bin_dir="$HOME/.local/bin"

mkdir -p "$bin_dir"
chmod +x "$module_root/scripts/yt-dlp-mpv" || true
ln -sf "$module_root/scripts/yt-dlp-mpv" "$bin_dir/yt-dlp-mpv"
