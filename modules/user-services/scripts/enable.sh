#!/usr/bin/env bash
# ==============================================================================
# Script: enable.sh (Ultimate Dynamic Orchestrator)
# Description: Synchronizes Systemd user units based on enabled modules in host config.
#              Directly scans repository directories for maximum reliability.
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

  for key in DCLI_HOST DCLI_ACTIVE_HOST DCLI_TARGET_HOST; do
    if [[ -n "${!key:-}" ]]; then host="${!key}"; break; fi
  done

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
    log_warn "Host configuration '$host_file' not found."
    return 1
  fi

  log_info "Parsing enabled modules from $host.yaml..."
  
  # Read the list between 'enabled_modules:' and the next top-level key
  local in_list=false
  while IFS= read -r line || [[ -n "$line" ]]; do
    if [[ "$line" =~ ^enabled_modules: ]]; then
      in_list=true
      continue
    elif [[ "$line" =~ ^[a-zA-Z] && "$in_list" == true ]]; then
      in_list=false
    fi

    if [[ "$in_list" == true && "$line" =~ ^[[:space:]]*-[[:space:]]+ ]]; then
      local m
      m=$(echo "$line" | sed -E 's/^[[:space:]]*- //;s/[[:space:]]*#.*$//' | xargs)
      [[ -n "$m" ]] && enabled_modules["$m"]=1
    fi
  done < "$host_file"
}

is_module_enabled() {
  local module="$1"
  [[ -n "${enabled_modules[$module]:-}" ]]
}

skip_automanaged_unit() {
  local module="$1"
  local unit="$2"

  case "${module}:${unit}" in
    connect:kdeconnect.service|connect:kdeconnect.timer|connect:kdeconnect-indicator.service)
      # KDE Connect has compositor/session-aware enablement handled by the
      # connect module's own install hook. Enabling it blindly here can pull
      # graphical-session.target too early and break UWSM compositor startup.
      return 0
      ;;
  esac

  return 1
}

# --- Service Synchronization ---

sync_user_units() {
  log_info "Starting Systemd unit synchronization..."
  run_as_user systemctl --user daemon-reload >/dev/null 2>&1 || true

  local module_path module_name
  for module_path in "$REPO_ROOT/modules"/*; do
    [[ -d "$module_path" ]] || continue
    module_name="$(basename "$module_path")"
    
    local systemd_dir="$module_path/dotfiles/systemd/user"
    [[ -d "$systemd_dir" ]] || continue

    # Find all user units in this module's repo directory, including sockets.
    while IFS= read -r -d '' unit_file; do
      local unit_name
      unit_name="$(basename "$unit_file")"

      if skip_automanaged_unit "$module_name" "$unit_name"; then
        continue
      fi
      
      if is_module_enabled "$module_name"; then
        # Check if already enabled to minimize noise
        if ! run_as_user systemctl --user is-enabled "$unit_name" >/dev/null 2>&1; then
          # Enable using the ABSOLUTE path in the repository
          # This ensures Systemd can find it even before dcli links it.
          if run_as_user systemctl --user enable "$unit_file" >/dev/null 2>&1; then
            echo "  -> Enabled $unit_name ($module_name)"
          else
            log_warn "Failed to enable $unit_name"
          fi
        fi
      else
        # Automatically disable and stop units from inactive modules
        if run_as_user systemctl --user is-enabled "$unit_name" >/dev/null 2>&1; then
          run_as_user systemctl --user disable --now "$unit_name" >/dev/null 2>&1 || true
          log_warn "Disabled $unit_name (module '$module_name' is inactive)"
        fi
      fi
    done < <(find "$systemd_dir" -maxdepth 2 -type f \( -name "*.service" -o -name "*.timer" -o -name "*.target" -o -name "*.socket" \) -print0)
  done
}

# --- Main ---

main() {
  local host
  host=$(active_host_from_config)
  load_enabled_modules "$host"
  
  if [[ ${#enabled_modules[@]} -eq 0 ]]; then
    die "No enabled modules found for host '$host'. Check your YAML format."
  fi

  sync_user_units
  
  log_success "All user services are now in sync with $host.yaml"
}

main "$@"
