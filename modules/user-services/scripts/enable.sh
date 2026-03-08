#!/usr/bin/env bash
# ==============================================================================
# Script: enable.sh (Robust & Fully Dynamic)
# Description: Synchronizes Systemd user units based on enabled modules.
#              Uses direct repo paths to ensure enabling works before dotfile sync.
# ==============================================================================

set -euo pipefail

# Repository root discovery
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/../../.." && pwd)"

# Source the core DCLI library
source "$REPO_ROOT/modules/base/lib/core.sh"

# --- Configuration Discovery ---

active_host_from_config() {
  local host=""
  local config_file="$REPO_ROOT/config.yaml"

  # 1. Check environment variables
  for key in DCLI_HOST DCLI_ACTIVE_HOST DCLI_TARGET_HOST; do
    if [[ -n "${!key:-}" ]]; then
      host="${!key}"
      break
    fi
  done

  # 2. Fallback to config.yaml
  if [[ -z "$host" && -f "$config_file" ]]; then
    host="$(awk -F':[[:space:]]*' '/^[[:space:]]*host:[[:space:]]*/ {gsub(/["'\'']/, "", $2); print $2; exit}' "$config_file")"
  fi

  printf '%s\n' "${host:-hay}"
}

declare -A enabled_modules=()

load_enabled_modules() {
  local host="$1"
  local host_file="$REPO_ROOT/hosts/${host}.yaml"

  if [[ ! -f "$host_file" ]]; then
    log_warn "Host configuration '$host_file' not found. Enabling all modules."
    return 1
  fi

  log_info "Loading enabled modules from $host.yaml"
  
  # More robust YAML list parsing using sed/grep
  # Matches lines like "  - module_name" within the enabled_modules block
  local modules
  modules=$(sed -n '/^enabled_modules:/,/^[^ -]/p' "$host_file" | grep -E "^[[:space:]]*- " | sed -E 's/^[[:space:]]*- //;s/[[:space:]]*#.*$//')
  
  for m in $modules; do
    enabled_modules["$m"]=1
  done
}

is_module_enabled() {
  local module="$1"
  [[ ${#enabled_modules[@]} -eq 0 ]] && return 0
  [[ -n "${enabled_modules[$module]:-}" ]]
}

# --- Unit Discovery & Management ---

# Get source path and target name for systemd units in a module
discover_unit_mappings() {
  local module_file="$1"
  local module_dir
  module_dir="$(dirname "$module_file")"
  
  # Find source/target pairs for systemd user units
  # Format: source_path|unit_name
  awk -v dir="$module_dir" '
    /source:.*systemd\/user\// { src=$2; gsub(/["'\'']/, "", src) }
    /target:.*systemd\/user\// { 
      dst=$2; gsub(/["'\'']/, "", dst);
      sub(/.*\//, "", dst);
      if (src != "") {
        # Construct absolute source path (relative to module dir)
        abs_src = dir "/" src;
        print abs_src "|" dst;
        src = "";
      }
    }
  ' "$module_file"
}

sync_user_units() {
  log_info "Synchronizing Systemd user units..."
  run_as_user systemctl --user daemon-reload >/dev/null 2>&1 || true

  local module_path module_name
  for module_path in "$REPO_ROOT/modules"/*; do
    [[ -d "$module_path" ]] || continue
    module_name="$(basename "$module_path")"
    local yaml="$module_path/module.yaml"
    
    [[ -f "$yaml" ]] || continue
    
    # Process each unit mapping
    while IFS='|' read -r src_path unit_name; do
      [[ -n "$unit_name" ]] || continue
      
      if is_module_enabled "$module_name"; then
        # Check if already enabled to reduce noise
        if ! run_as_user systemctl --user is-enabled "$unit_name" >/dev/null 2>&1; then
          # Use absolute path to enable, ensuring it works even if not yet linked
          if run_as_user systemctl --user enable "$src_path" >/dev/null 2>&1; then
            echo "  -> Enabled $unit_name ($module_name)"
          fi
        fi
      else
        # Disable units from inactive modules
        if run_as_user systemctl --user is-enabled "$unit_name" >/dev/null 2>&1; then
          run_as_user systemctl --user disable --now "$unit_name" >/dev/null 2>&1 || true
          log_warn "Disabled $unit_name (module '$module_name' is inactive)"
        fi
      fi
    done < <(discover_unit_mappings "$yaml")
  done
}

# --- Main Execution ---

main() {
  log_info "Starting service synchronization for: $REAL_USER"
  
  local host
  host=$(active_host_from_config)
  load_enabled_modules "$host" || true
  
  sync_user_units
  
  log_success "Service synchronization complete."
}

main "$@"
