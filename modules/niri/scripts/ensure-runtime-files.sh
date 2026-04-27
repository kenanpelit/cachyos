#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
repo_root="$(cd "$script_dir/../../.." && pwd)"
source "$repo_root/modules/base/lib/core.sh"

NIRI_DIR="$USER_HOME/.config/niri"
RUNTIME_DIR="$NIRI_DIR/runtime"
LOCAL_CONFIG_FILE="$NIRI_DIR/local.kdl"
RUNTIME_DEBUG_FILE="$RUNTIME_DIR/debug.kdl"
STATIC_CONFIG_SOURCE="$repo_root/modules/niri/dotfiles/niri/config.kdl"
STATIC_CONFIG_TARGET="$NIRI_DIR/config.kdl"
STATIC_OUTPUTS_SOURCE="$repo_root/modules/niri/dotfiles/niri/outputs.kdl"
STATIC_OUTPUTS_TARGET="$NIRI_DIR/outputs.kdl"
STATIC_CONF_SOURCE="$repo_root/modules/niri/dotfiles/niri/conf"
STATIC_CONF_TARGET="$NIRI_DIR/conf"
STATIC_GENERATED_SOURCE="$repo_root/modules/niri/dotfiles/niri/generated"
STATIC_GENERATED_TARGET="$NIRI_DIR/generated"
LEGACY_ENV_FILE="$USER_HOME/.config/environment.d/10-niri-env.conf"
LEGACY_PRIORITY_DROPIN="$USER_HOME/.config/systemd/user/niri.service.d/10-priority.conf"
LEGACY_DESKTOP_SETTINGS_UNIT="$USER_HOME/.config/systemd/user/niri-desktop-settings.service"
LEGACY_DESKTOP_SETTINGS_WANTS_LINK="$USER_HOME/.config/systemd/user/niri-post-daemons.target.wants/niri-desktop-settings.service"
USER_GROUP=""
if [ "$(id -u)" -eq 0 ]; then
  USER_GROUP="$(id -gn "$REAL_USER" 2>/dev/null || true)"
fi

if [ "$(id -u)" -eq 0 ] && [ -n "$USER_GROUP" ]; then
  install -d -m0755 -o "$REAL_USER" -g "$USER_GROUP" "$NIRI_DIR"
  chown "$REAL_USER:$USER_GROUP" "$NIRI_DIR" 2>/dev/null || true
else
  mkdir -p "$NIRI_DIR"
fi

if [ "$(id -u)" -eq 0 ] && [ -n "$USER_GROUP" ]; then
  install -d -m0755 -o "$REAL_USER" -g "$USER_GROUP" "$RUNTIME_DIR"
  chown -R "$REAL_USER:$USER_GROUP" "$RUNTIME_DIR" 2>/dev/null || true
else
  mkdir -p "$RUNTIME_DIR"
fi

# Local/debug overrides are kept as regular user files so config reloads do not
# spam optional-include warnings, while the repo remains the source of truth.
if [ "$(id -u)" -eq 0 ]; then
  run_as_user touch "$LOCAL_CONFIG_FILE" "$RUNTIME_DEBUG_FILE"
else
  touch "$LOCAL_CONFIG_FILE" "$RUNTIME_DEBUG_FILE"
fi

if [ -f "$STATIC_OUTPUTS_SOURCE" ]; then
  # Keep config assets as symlinks so the repo remains the single source of truth.
  run_as_user ln -sfnT "$STATIC_CONFIG_SOURCE" "$STATIC_CONFIG_TARGET"
  # Keep outputs.kdl as a symlink so the repo remains the single source of truth.
  run_as_user ln -sfnT "$STATIC_OUTPUTS_SOURCE" "$STATIC_OUTPUTS_TARGET"
fi

if [ -d "$STATIC_CONF_SOURCE" ]; then
  run_as_user ln -sfnT "$STATIC_CONF_SOURCE" "$STATIC_CONF_TARGET"
fi

if [ -d "$STATIC_GENERATED_SOURCE" ]; then
  run_as_user ln -sfnT "$STATIC_GENERATED_SOURCE" "$STATIC_GENERATED_TARGET"
fi

render_profile_script="$script_dir/render-profile.sh"
render_workspace_assets_script="$script_dir/render-workspace-assets.sh"
render_theme_script="$script_dir/render-theme.sh"
render_background_effects_script="$script_dir/render-background-effects.sh"
render_keybind_cheatsheet_script="$script_dir/render-keybind-cheatsheet.sh"
shared_monitor_assets_script="$repo_root/shared/wm/render-monitor-assets.sh"

legacy_runtime_files=(
  "$RUNTIME_DIR/cursor.kdl"
  "$RUNTIME_DIR/windowrules.kdl"
  "$RUNTIME_DIR/alttab.kdl"
  "$RUNTIME_DIR/layout.kdl"
)

for legacy_path in "${legacy_runtime_files[@]}"; do
  rm -f "$legacy_path" 2>/dev/null || true
done

rm -f "$LEGACY_ENV_FILE" 2>/dev/null || true
rm -f "$LEGACY_PRIORITY_DROPIN" 2>/dev/null || true
rm -f "$LEGACY_DESKTOP_SETTINGS_UNIT" 2>/dev/null || true
rm -f "$LEGACY_DESKTOP_SETTINGS_WANTS_LINK" 2>/dev/null || true

if [[ -x "$shared_monitor_assets_script" ]]; then
  if [ "$(id -u)" -eq 0 ]; then
    run_as_user "$shared_monitor_assets_script"
  else
    "$shared_monitor_assets_script"
  fi
fi

if [[ -x "$render_theme_script" ]]; then
  if [ "$(id -u)" -eq 0 ]; then
    run_as_user "$render_theme_script"
  else
    "$render_theme_script"
  fi
fi

if [[ -x "$render_background_effects_script" ]]; then
  if [ "$(id -u)" -eq 0 ]; then
    run_as_user "$render_background_effects_script"
  else
    "$render_background_effects_script"
  fi
fi

if [[ -x "$render_profile_script" ]]; then
  if [ "$(id -u)" -eq 0 ]; then
    run_as_user "$render_profile_script"
  else
    "$render_profile_script"
  fi
fi

if [[ -x "$render_workspace_assets_script" ]]; then
  if [ "$(id -u)" -eq 0 ]; then
    run_as_user env NIRI_RUNTIME_DIR="$RUNTIME_DIR" "$render_workspace_assets_script" --runtime-dir "$RUNTIME_DIR"
  else
    NIRI_RUNTIME_DIR="$RUNTIME_DIR" "$render_workspace_assets_script" --runtime-dir "$RUNTIME_DIR"
  fi
fi

if [[ -x "$render_keybind_cheatsheet_script" ]]; then
  if [ "$(id -u)" -eq 0 ]; then
    run_as_user "$render_keybind_cheatsheet_script"
  else
    "$render_keybind_cheatsheet_script"
  fi
fi

if [[ -f "$STATIC_GENERATED_SOURCE/keybind-cheatsheet.conf" ]]; then
  run_as_user ln -sfnT "$STATIC_GENERATED_SOURCE/keybind-cheatsheet.conf" "$RUNTIME_DIR/keybind-cheatsheet.conf"
fi

if [ "$(id -u)" -eq 0 ] && [ -n "$USER_GROUP" ]; then
  chown -R "$REAL_USER:$USER_GROUP" "$RUNTIME_DIR" 2>/dev/null || true
fi

# Run health check validation
if [[ -x "$script_dir/validate.sh" ]]; then
  if [ "$(id -u)" -eq 0 ]; then
    run_as_user "$script_dir/validate.sh"
  else
    "$script_dir/validate.sh"
  fi
fi

if command -v systemctl >/dev/null 2>&1; then
  run_as_user systemctl --user daemon-reload >/dev/null 2>&1 || true
fi
