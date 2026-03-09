#!/usr/bin/env bash
set -euo pipefail

# Repository root discovery
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/../../.." && pwd)"

# Source the core DCLI library
source "$REPO_ROOT/modules/base/lib/core.sh"

bin_dir="$USER_HOME/.local/bin"
mkdir -p "$bin_dir" "$USER_HOME/.config/helium-launcher"

# Link the launcher scripts
ln -sf "$REPO_ROOT/modules/helium/scripts/profile_helium.sh" "$bin_dir/profile_helium"
ln -sf "$REPO_ROOT/modules/helium/scripts/profile_helium.sh" "$bin_dir/helium-launcher"

# Ensure writable log file exists
: >"$USER_HOME/.config/helium-launcher/helium-launcher.log" 2>/dev/null || true
chmod u+rw "$USER_HOME/.config/helium-launcher/helium-launcher.log" 2>/dev/null || true

log_success "Helium launcher installed to $bin_dir"
