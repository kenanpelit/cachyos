#!/usr/bin/env bash
set -euo pipefail

# Repository root (this script lives at modules/user-services/scripts/enable.sh)
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/../../.." && pwd)"

# Source the core DCLI library
source "$REPO_ROOT/modules/base/lib/core.sh"

# Auto-discovered service:module map from modules/*/module.yaml dotfiles
# entries that target ~/.config/systemd/user/*.service|*.timer.
service_specs=()

active_host_from_config() {
  local host=""
  local config_file="$REPO_ROOT/config.yaml"

  # Prefer explicit env from caller if present.
  for key in DCLI_HOST DCLI_ACTIVE_HOST DCLI_TARGET_HOST; do
    if [[ -n "${!key:-}" ]]; then
      host="${!key}"
      break
    fi
  done

  if [[ -z "$host" && -f "$config_file" ]]; then
    host="$(
      awk -F':[[:space:]]*' '
        /^[[:space:]]*host:[[:space:]]*/ {
          gsub(/["'"'"']/, "", $2);
          print $2;
          exit
        }
      ' "$config_file"
    )"
  fi

  printf '%s\n' "$host"
}

declare -A enabled_modules=()
module_filter_active=false

load_enabled_modules() {
  local host="$1"
  local host_file="$REPO_ROOT/hosts/${host}.yaml"

  if [[ -z "$host" || ! -f "$host_file" ]]; then
    echo "  -> Host module list unavailable; falling back to legacy enable behavior"
    return 1
  fi

  while IFS= read -r module; do
    [[ -n "$module" ]] || continue
    enabled_modules["$module"]=1
  done < <(
    awk '
      BEGIN { in_list = 0 }
      /^[[:space:]]*enabled_modules:[[:space:]]*$/ { in_list = 1; next }
      in_list {
        if ($0 ~ /^[[:space:]]*-[[:space:]]*/) {
          line = $0
          sub(/^[[:space:]]*-[[:space:]]*/, "", line)
          sub(/[[:space:]]*#.*/, "", line)
          gsub(/^[[:space:]]+|[[:space:]]+$/, "", line)
          if (line != "") print line
          next
        }
        if ($0 ~ /^[[:space:]]*#/ || $0 ~ /^[[:space:]]*$/) next
        in_list = 0
      }
    ' "$host_file"
  )

  if ((${#enabled_modules[@]} > 0)); then
    module_filter_active=true
    echo "  -> Active host: $host (${#enabled_modules[@]} enabled modules detected)"
  fi
}

module_enabled() {
  local module="$1"
  if [[ "$module_filter_active" != true ]]; then
    return 0
  fi
  [[ -n "${enabled_modules[$module]:-}" ]]
}

service_exists() {
  local unit="$1"
  run_as_user systemctl --user list-unit-files "$unit" >/dev/null 2>&1
}

enable_service_if_present() {
  local unit="$1"
  if service_exists "$unit"; then
    # Use reenable to purge stale WantedBy symlinks when unit install targets change.
    if run_as_user systemctl --user reenable "$unit" >/dev/null 2>&1; then
      echo "  -> Enabled $unit"
    else
      echo "  -> Skipped $unit (enable failed or not installable)"
    fi
  else
    echo "  -> Skipped $unit (not found or user bus inaccessible)"
  fi
}

disable_service_if_present() {
  local unit="$1"
  if service_exists "$unit"; then
    if run_as_user systemctl --user disable --now "$unit" >/dev/null 2>&1; then
      echo "  -> Disabled $unit (module disabled)"
    fi
  fi
}

discover_module_units() {
  local module="$1"
  local module_file="$REPO_ROOT/modules/${module}/module.yaml"
  [[ -f "$module_file" ]] || return 0

  awk '
    /^[[:space:]]*target:[[:space:]]*~\/\.config\/systemd\/user\// {
      line = $0
      sub(/^[[:space:]]*target:[[:space:]]*~\/\.config\/systemd\/user\//, "", line)
      sub(/[[:space:]]*#.*/, "", line)
      gsub(/["'"'"']/, "", line)
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", line)
      if (line ~ /\.(service|timer)$/) print line
    }
  ' "$module_file"
}

seed_unit_file_from_repo() {
  local module="$1"
  local unit="$2"
  local src="$REPO_ROOT/modules/${module}/dotfiles/systemd/user/${unit}"
  local dst="$USER_HOME/.config/systemd/user/${unit}"

  [[ -f "$src" ]] || return 0
  safe_install "$src" "$dst"
}

build_service_specs() {
  local module_dir module unit spec
  declare -A seen_specs=()
  service_specs=()

  for module_dir in "$REPO_ROOT"/modules/*; do
    [[ -d "$module_dir" ]] || continue
    module="$(basename "$module_dir")"

    while IFS= read -r unit; do
      [[ -n "$unit" ]] || continue
      spec="${unit}:${module}"
      [[ -n "${seen_specs[$spec]:-}" ]] && continue
      seen_specs["$spec"]=1
      service_specs+=("$spec")
    done < <(discover_module_units "$module")
  done
}

echo "Enabling user services for user: $REAL_USER..."

# Resolve host/module state once; allows disabling stale units if module is not enabled.
ACTIVE_HOST="$(active_host_from_config)"
load_enabled_modules "$ACTIVE_HOST" || true
build_service_specs

# Ensure MPD uses user-scoped config, not /etc/mpd.conf (/var/lib/mpd),
# only when mpd module is enabled.
if module_enabled "mpd"; then
  safe_install \
    "$REPO_ROOT/modules/mpd/dotfiles/mpd/mpd.conf" \
    "$USER_HOME/.config/mpd/mpd.conf"
  safe_install \
    "$REPO_ROOT/modules/mpd/dotfiles/systemd/user/mpd.service" \
    "$USER_HOME/.config/systemd/user/mpd.service"
fi

# Ensure ppp auto-profile units exist before enable pass when niri module is enabled.
if module_enabled "niri"; then
  safe_install \
    "$REPO_ROOT/modules/niri/dotfiles/systemd/user/ppp-auto-profile.service" \
    "$USER_HOME/.config/systemd/user/ppp-auto-profile.service"
  safe_install \
    "$REPO_ROOT/modules/niri/dotfiles/systemd/user/ppp-auto-profile.timer" \
    "$USER_HOME/.config/systemd/user/ppp-auto-profile.timer"
fi

# Seed service/timer unit files before enable pass.
# user-services post-install currently runs before the global dotfile sync phase,
# so units may not exist under ~/.config/systemd/user yet.
for spec in $(printf '%s\n' "${service_specs[@]}" | sort); do
  service="${spec%%:*}"
  module="${spec#*:}"
  if module_enabled "$module"; then
    seed_unit_file_from_repo "$module" "$service"
  fi
done

run_as_user systemctl --user daemon-reload >/dev/null 2>&1 || true

for spec in $(printf '%s\n' "${service_specs[@]}" | sort); do
  service="${spec%%:*}"
  module="${spec#*:}"

  if module_enabled "$module"; then
    enable_service_if_present "$service"
  else
    # Keep stale units under control when auto_prune=false.
    disable_service_if_present "$service"
  fi
done

# Legacy cleanup: units retired from the startup graph but possibly still enabled.
legacy_disable_units=(
  "niri-ready.service"
)
for unit in "${legacy_disable_units[@]}"; do
  disable_service_if_present "$unit"
done

# Migration cleanup: these units moved from niri-session.target.wants to
# niri-daemons.target.wants. Remove stale links so ordering stays deterministic.
legacy_niri_session_links=(
  "niri-blueman-applet.service"
  "niri-nm-applet.service"
  "niri-polkit-agent.service"
  "niri-niriswitcher.service"
  "niri-sticky.service"
  "niri-snapper-tools-check.service"
)
for unit in "${legacy_niri_session_links[@]}"; do
  run_as_user rm -f "$USER_HOME/.config/systemd/user/niri-session.target.wants/$unit" >/dev/null 2>&1 || true
done

# Migration cleanup: noctalia.service moved from default.target to niri-daemons.target.
run_as_user rm -f "$USER_HOME/.config/systemd/user/default.target.wants/noctalia.service" >/dev/null 2>&1 || true

# PipeWire stacks often pull compatibility references to legacy user units.
# Mask them to avoid not-found noise in `systemctl --user list-units --all`.
if run_as_user systemctl --user list-unit-files pipewire-pulse.service >/dev/null 2>&1; then
  for legacy in pulseaudio.service pipewire-media-session.service; do
    run_as_user systemctl --user stop "$legacy" >/dev/null 2>&1 || true
    run_as_user systemctl --user mask "$legacy" >/dev/null 2>&1 || true
    echo "  -> Masked $legacy (PipeWire compatibility)"
  done
fi
