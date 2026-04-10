#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
repo_root="$(cd "$script_dir/../../.." && pwd)"
source "$repo_root/modules/base/lib/core.sh"

render_theme_script="$script_dir/render-theme.sh"
render_monitors_script="$script_dir/render-monitors.sh"
render_workspace_routing_script="$script_dir/render-workspace-routing.sh"
hypr_config="$USER_HOME/.config/hypr/hyprland.conf"

shell_scripts=(
  "$repo_root/modules/scripts/bin/hypr-bootstrap.sh"
  "$repo_root/modules/scripts/bin/hypr-osc.sh"
  "$repo_root/modules/scripts/bin/hypr-session-common.sh"
  "$repo_root/modules/scripts/bin/hypr-session-init.sh"
  "$repo_root/modules/scripts/bin/hypr-desktop-settings.sh"
  "$repo_root/modules/scripts/bin/hypr-post-bootstrap.sh"
  "$render_theme_script"
  "$render_monitors_script"
  "$render_workspace_routing_script"
)

log_info "Validating Hyprland generated files..."

if "$render_theme_script" --check >/dev/null 2>&1; then
  log_success "Rendered Hyprland theme files are in sync!"
else
  log_error "Rendered Hyprland theme drift detected!"
  "$render_theme_script" --check
  exit 1
fi

if "$render_monitors_script" --check >/dev/null 2>&1; then
  log_success "Rendered Hyprland monitor files are in sync!"
else
  log_error "Rendered Hyprland monitor drift detected!"
  "$render_monitors_script" --check
  exit 1
fi

if "$render_workspace_routing_script" --check >/dev/null 2>&1; then
  log_success "Rendered Hyprland workspace routing files are in sync!"
else
  log_error "Rendered Hyprland workspace routing drift detected!"
  "$render_workspace_routing_script" --check
  exit 1
fi

log_info "Validating Hyprland helper shell syntax..."

if bash -n "${shell_scripts[@]}"; then
  log_success "Hyprland helper scripts parsed successfully!"
else
  log_error "Hyprland helper shell syntax validation failed!"
  exit 1
fi

if command -v Hyprland >/dev/null 2>&1 && [[ -f "$hypr_config" ]]; then
  log_info "Verifying installed Hyprland config..."
  if Hyprland --verify-config -c "$hypr_config" >/dev/null 2>&1; then
    log_success "Installed Hyprland config verifies successfully!"
  else
    log_error "Installed Hyprland config verification failed!"
    Hyprland --verify-config -c "$hypr_config"
    exit 1
  fi
fi

if command -v hyprctl >/dev/null 2>&1; then
  if config_errors="$(hyprctl configerrors 2>/dev/null)"; then
    if [[ -n "${config_errors}" ]]; then
      log_error "Live Hyprland session reports config errors!"
      printf '%s\n' "${config_errors}"
      exit 1
    fi
  fi
fi
