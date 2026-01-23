#!/usr/bin/env bash
set -euo pipefail

module_root="$(cd "$(dirname "$0")/.." && pwd)"
bin_dir="$HOME/.local/bin"

mkdir -p "$bin_dir"
ln -sf "$module_root/scripts/run-anydesk" "$bin_dir/run-anydesk"
