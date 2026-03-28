#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
repo_root="$(cd "$script_dir/../../.." && pwd)"
source "$repo_root/modules/base/lib/core.sh"

render_theme_script="$script_dir/render-theme.sh"
render_monitors_script="$script_dir/render-monitors.sh"

shell_scripts=(
  "$repo_root/modules/scripts/bin/hypr-bootstrap.sh"
  "$repo_root/modules/scripts/bin/hypr-osc.sh"
  "$repo_root/modules/scripts/bin/hypr-session-common.sh"
  "$repo_root/modules/scripts/bin/hypr-session-init.sh"
  "$repo_root/modules/scripts/bin/hypr-desktop-settings.sh"
  "$repo_root/modules/scripts/bin/hypr-post-bootstrap.sh"
  "$render_theme_script"
  "$render_monitors_script"
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

log_info "Validating Hyprland helper shell syntax..."

if bash -n "${shell_scripts[@]}"; then
  log_success "Hyprland helper scripts parsed successfully!"
else
  log_error "Hyprland helper shell syntax validation failed!"
  exit 1
fi
