#!/usr/bin/env bash
set -euo pipefail

# Repository root discovery
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/../../.." && pwd)"

# Source the core DCLI library
source "$REPO_ROOT/modules/base/lib/core.sh"

bin_dir="$USER_HOME/.local/bin"
config_dir="$USER_HOME/.config/helium-launcher"
launcher_src="$REPO_ROOT/modules/helium/scripts/profile_helium.sh"
log_file="$config_dir/helium-launcher.log"

ensure_user_dir() {
  local dir="$1"
  local backup

  if run_as_user test -e "$dir" && ! run_as_user test -d "$dir"; then
    backup="${dir}.bak.$(date +%Y%m%d-%H%M%S)"
    log_warn "$dir exists but is not a directory; moving it to $backup"
    run_as_user mv "$dir" "$backup"
  fi

  run_as_user mkdir -p "$dir"
}

ensure_user_dir "$bin_dir"
ensure_user_dir "$config_dir"

# Link the launcher scripts
run_as_user ln -sfn "$launcher_src" "$bin_dir/profile_helium"
run_as_user ln -sfn "$launcher_src" "$bin_dir/helium-launcher"

# Ensure writable log file exists
run_as_user touch "$log_file"
run_as_user chmod u+rw "$log_file"

log_success "Helium launcher installed to $bin_dir"
