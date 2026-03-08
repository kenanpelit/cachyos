#!/usr/bin/env bash
set -euo pipefail

# Repository root (this script lives at modules/user-services/scripts/enable.sh)
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/../../.." && pwd)"

# Source the core DCLI library
source "$REPO_ROOT/modules/base/lib/core.sh"

# service:module map
service_specs=(
  "mpd.service:mpd"
  "fusuma.service:fusuma"
  "hyprland-polkit-agent.service:hyprland"
  "hypr-nm-applet.service:hyprland"
  "niri-nm-applet.service:niri"
  "niri-blueman-applet.service:niri"
  "niri-snapper-tools-check.service:niri"
  "hypr-clip-persist.service:hyprland"
  "hypr-init.service:hyprland"
  "stasis.timer:stasis"
  "walker.service:walker"
  "walker.timer:walker"
  "elephant.service:walker"
  "geoclue-agent.timer:niri"
  "flatpak-managed-install.timer:flatpak"
  "hyprland-bt-autoconnect.timer:bt"
  "niri-bt-autoconnect.timer:bt"
  "kdeconnect.timer:connect"
  "noctalia.service:noctalia"
  "niri-bootstrap.service:niri"
  "niri-sticky.service:niri"
  "niri-niriswitcher.service:niri"
  "niri-polkit-agent.service:niri"
  "copyq.timer:copyq"
  "ppp-auto-profile.timer:niri"
  "transmission.service:transmission"
)

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
    run_as_user systemctl --user enable "$unit" >/dev/null 2>&1 || true
    echo "  -> Enabled $unit"
  else
    echo "  -> Skipped $unit (not found or user bus inaccessible)"
  fi
}

disable_service_if_present() {
  local unit="$1"
  if service_exists "$unit"; then
    run_as_user systemctl --user disable --now "$unit" >/dev/null 2>&1 || true
    echo "  -> Disabled $unit (module disabled)"
  fi
}

echo "Enabling user services for user: $REAL_USER..."

# Resolve host/module state once; allows disabling stale units if module is not enabled.
ACTIVE_HOST="$(active_host_from_config)"
load_enabled_modules "$ACTIVE_HOST" || true

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

run_as_user systemctl --user daemon-reload >/dev/null 2>&1 || true

for spec in "${service_specs[@]}"; do
  service="${spec%%:*}"
  module="${spec#*:}"

  if module_enabled "$module"; then
    enable_service_if_present "$service"
  else
    # Keep stale units under control when auto_prune=false.
    disable_service_if_present "$service"
  fi
done

# PipeWire stacks often pull compatibility references to legacy user units.
# Mask them to avoid not-found noise in `systemctl --user list-units --all`.
if run_as_user systemctl --user list-unit-files pipewire-pulse.service >/dev/null 2>&1; then
  for legacy in pulseaudio.service pipewire-media-session.service; do
    run_as_user systemctl --user stop "$legacy" >/dev/null 2>&1 || true
    run_as_user systemctl --user mask "$legacy" >/dev/null 2>&1 || true
    echo "  -> Masked $legacy (PipeWire compatibility)"
  done
fi
