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
    cliphist:cliphist.service)
      # Noctalia owns the live cliphist ingestion watchers. The cliphist module
      # only ships config and a legacy unit, so keep user-services from
      # re-enabling the duplicate watcher.
      return 0
      ;;
    xdg-portal:xdg-desktop-portal-delayed.service|xdg-portal:xdg-desktop-portal-delayed.timer)
      # The xdg-portal module manages delayed portal orchestration itself so it
      # can stay bound to compositor session targets instead of default.target.
      return 0
      ;;
    flatpak:flatpak-managed-install.service)
      # Flatpak managed installs are intentionally timer-driven; only the timer
      # should be enabled.
      return 0
      ;;
    sessions:geoclue-agent.service)
      # Geoclue is started by its delayed timer, not directly by the service.
      return 0
      ;;
    sessions:ppp-auto-profile.service)
      # PPP auto-profile is intentionally timer-driven; only the timer should be
      # enabled by the generic synchronizer.
      return 0
      ;;
    sunsetr:sunsetr.service|sunsetr:sunsetr-auto-profile.timer)
      # Sunsetr manages its own Niri-scoped enablement and reenable lifecycle in
      # the module install hook. Letting the generic synchronizer touch these
      # units every sync creates noisy duplicate enable passes.
      return 0
      ;;
  esac

  return 1
}

unit_install_entries() {
  local unit_file="$1"
  local key="$2"
  local line value in_install=false

  while IFS= read -r line || [[ -n "$line" ]]; do
    case "$line" in
      "[Install]")
        in_install=true
        continue
        ;;
      \[*\])
        $in_install && break
        ;;
    esac

    $in_install || continue
    [[ "${line#\#}" == "$line" ]] || continue

    case "$line" in
      "${key}"=*)
        value="${line#${key}=}"
        for value in $value; do
          printf '%s\n' "$value"
        done
        ;;
    esac
  done < "$unit_file"
}

unit_has_install_directives() {
  local unit_file="$1"
  local line in_install=false

  while IFS= read -r line || [[ -n "$line" ]]; do
    case "$line" in
      "[Install]")
        in_install=true
        continue
        ;;
      \[*\])
        $in_install && break
        ;;
    esac

    $in_install || continue
    [[ -n "${line//[[:space:]]/}" ]] || continue
    [[ "${line#\#}" == "$line" ]] || continue
    return 0
  done < "$unit_file"

  return 1
}

unit_file_is_linked() {
  local unit_file="$1"
  local unit_name="$2"
  local user_home="${USER_HOME:-$HOME}"
  local linked_path="${user_home}/.config/systemd/user/${unit_name}"
  local linked_target unit_target

  [[ -L "$linked_path" ]] || return 1
  linked_target="$(readlink -f "$linked_path" 2>/dev/null || true)"
  unit_target="$(readlink -f "$unit_file" 2>/dev/null || true)"
  [[ -n "$linked_target" && -n "$unit_target" && "$linked_target" == "$unit_target" ]]
}

unit_links_need_resync() {
  local unit_file="$1"
  local unit_name="$2"
  local user_home="${USER_HOME:-$HOME}"
  local systemd_user_dir="${user_home}/.config/systemd/user"
  local entry rel target
  local -A wanted=()
  local -A required=()
  local -A existing_wanted=()
  local -A existing_required=()

  while IFS= read -r entry; do
    [[ -n "$entry" ]] || continue
    wanted["$entry"]=1
  done < <(unit_install_entries "$unit_file" "WantedBy")

  while IFS= read -r entry; do
    [[ -n "$entry" ]] || continue
    required["$entry"]=1
  done < <(unit_install_entries "$unit_file" "RequiredBy")

  while IFS= read -r rel; do
    [[ -n "$rel" ]] || continue
    case "$rel" in
      *.wants/"$unit_name")
        target="${rel%%.wants/*}"
        existing_wanted["$target"]=1
        ;;
      *.requires/"$unit_name")
        target="${rel%%.requires/*}"
        existing_required["$target"]=1
        ;;
    esac
  done < <(find "$systemd_user_dir" -maxdepth 2 -type l \( -path "*/*.wants/$unit_name" -o -path "*/*.requires/$unit_name" \) -printf '%P\n' 2>/dev/null || true)

  for target in "${!wanted[@]}"; do
    [[ -n "${existing_wanted[$target]:-}" ]] || return 0
  done

  for target in "${!required[@]}"; do
    [[ -n "${existing_required[$target]:-}" ]] || return 0
  done

  for target in "${!existing_wanted[@]}"; do
    [[ -n "${wanted[$target]:-}" ]] || return 0
  done

  for target in "${!existing_required[@]}"; do
    [[ -n "${required[$target]:-}" ]] || return 0
  done

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
        if unit_has_install_directives "$unit_file"; then
          # Check if already enabled to minimize noise while still re-syncing
          # stale target.wants links after [Install] metadata changes.
          if run_as_user systemctl --user is-enabled "$unit_name" >/dev/null 2>&1; then
            if unit_links_need_resync "$unit_file" "$unit_name"; then
              if run_as_user systemctl --user reenable "$unit_file" >/dev/null 2>&1; then
                echo "  -> Re-enabled $unit_name ($module_name)"
              else
                log_warn "Failed to re-enable $unit_name"
              fi
            fi
          else
            # Enable using the ABSOLUTE path in the repository
            # This ensures Systemd can find it even before dcli links it.
            if run_as_user systemctl --user enable "$unit_file" >/dev/null 2>&1; then
              echo "  -> Enabled $unit_name ($module_name)"
            else
              log_warn "Failed to enable $unit_name"
            fi
          fi
        elif ! unit_file_is_linked "$unit_file" "$unit_name"; then
          # Units without [Install] only need a stable link so systemd can
          # load them before the dotfiles pass runs.
          if run_as_user systemctl --user link "$unit_file" >/dev/null 2>&1; then
            echo "  -> Linked $unit_name ($module_name)"
          else
            log_warn "Failed to link $unit_name"
          fi
        fi
      else
        # Automatically disable and stop units from inactive modules
        if unit_has_install_directives "$unit_file" && run_as_user systemctl --user is-enabled "$unit_name" >/dev/null 2>&1; then
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
