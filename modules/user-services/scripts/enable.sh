#!/usr/bin/env bash
# ==============================================================================
# Script: enable.sh (Modernized & Fully Dynamic)
# Description: Synchronizes Systemd user units based on enabled modules.
#              Automatically discovers units from module.yaml files.
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

  printf '%s\n' "${host:-hay}" # Default to 'hay' if completely unknown
}

declare -A enabled_modules=()

load_enabled_modules() {
  local host="$1"
  local host_file="$REPO_ROOT/hosts/${host}.yaml"

  if [[ ! -f "$host_file" ]]; then
    log_warn "Host configuration '$host_file' not found. Enabling all modules."
    return 1
  fi

  log_info "Loading enabled modules for host: $host"
  
  # Extract modules from YAML list format (- module_name)
  while IFS= read -r module; do
    [[ -n "$module" ]] && enabled_modules["$module"]=1
  done < <(awk '/^[[:space:]]*enabled_modules:[[:space:]]*$/ {in_list=1; next} /^[[:space:]]*[^ -]/ {in_list=0} in_list && /^[[:space:]]*- / {sub(/^[[:space:]]*- /, ""); sub(/[[:space:]]*#.*/, ""); print $1}' "$host_file")
}

is_module_enabled() {
  local module="$1"
  [[ ${#enabled_modules[@]} -eq 0 ]] && return 0 # If no host file, treat all as enabled
  [[ -n "${enabled_modules[$module]:-}" ]]
}

# --- Unit Discovery & Management ---

# Extract systemd units from module.yaml dotfiles section
discover_units_in_module() {
  local module_file="$1"
  [[ -f "$module_file" ]] || return 0
  
  # Find target paths that point to systemd user directory
  awk '/target:[[:space:]]*~\/\.config\/systemd\/user\// {
    line = $0
    sub(/.*\/user\//, "", line)
    sub(/[[:space:]]*#.*/, "", line)
    gsub(/["'\'']/, "", line)
    if (line ~ /\.(service|timer|target)$/) print line
  }' "$module_file"
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
    
    # Get units defined in this module
    local units
    units=$(discover_units_in_module "$yaml")
    
    for unit in $units; do
      if is_module_enabled "$module_name"; then
        if run_as_user systemctl --user enable "$unit" >/dev/null 2>&1; then
          echo "  -> Enabled $unit ($module_name)"
        fi
      else
        # Automatically disable and stop units from inactive modules
        if run_as_user systemctl --user is-enabled "$unit" >/dev/null 2>&1; then
          run_as_user systemctl --user disable --now "$unit" >/dev/null 2>&1 || true
          log_warn "Disabled $unit (module '$module_name' is inactive)"
        fi
      fi
    done
  done
}

# --- Main Execution ---

main() {
  log_info "Starting declarative service synchronization for: $REAL_USER"
  
  local host
  host=$(active_host_from_config)
  load_enabled_modules "$host" || true
  
  sync_user_units
  
  log_success "Service synchronization complete."
}

main "$@"
