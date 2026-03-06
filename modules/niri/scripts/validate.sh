#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
repo_root="$(cd "$script_dir/../../.." && pwd)"
source "$repo_root/modules/base/lib/core.sh"

NIRI_CONFIG="$USER_HOME/.config/niri/config.kdl"

log_info "Validating Niri configuration..."

if [[ ! -f "$NIRI_CONFIG" ]]; then
    log_warn "Niri config file not found yet. Skipping validation."
    exit 0
fi

if ! command -v niri >/dev/null 2>&1; then
    log_warn "Niri binary not found in PATH. Cannot validate syntax."
    exit 0
fi

if niri validate -c "$NIRI_CONFIG" >/dev/null 2>&1; then
    log_success "Niri config is valid!"
else
    log_error "Niri config validation failed!"
    niri validate -c "$NIRI_CONFIG" # Show the error output
    exit 1
fi
