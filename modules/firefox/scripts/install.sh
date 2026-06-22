#!/usr/bin/env bash
set -euo pipefail

module_root="$(cd "$(dirname "$0")/.." && pwd)"
bin_dir="$HOME/.local/bin"

mkdir -p "$bin_dir"

# The firefox module owns firefoxctl (the Firefox analog of bravectl/heliumctl).
# Symlinked so edits to the repo source are live. Firefox needs no engine
# (native -P) and no ext catalog (AMO), so firefoxctl is the only firefox bin.
ln -sf "$module_root/scripts/firefoxctl.sh" "$bin_dir/firefoxctl"
