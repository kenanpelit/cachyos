#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
MODULE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
source "$REPO_ROOT/modules/base/lib/core.sh"

noctalia_template_dir="$MODULE_DIR/dotfiles/noctalia"
noctalia_config_dir="$USER_HOME/.config/noctalia"
noctalia_backup_root="$USER_HOME/.local/state/cachy/backups/noctalia"
user_systemd_dir="$USER_HOME/.config/systemd/user"
render_workspace_meta_script="$MODULE_DIR/scripts/render-workspace-meta.sh"

cleanup_legacy_noctalia_wants() {
  run_as_user rm -f \
    "$user_systemd_dir/default.target.wants/noctalia.service" \
    "$user_systemd_dir/graphical-session.target.wants/noctalia.service" \
    "$user_systemd_dir/hyprland-session.target.wants/noctalia.service" \
    "$user_systemd_dir/niri-session.target.wants/noctalia.service" \
    "$user_systemd_dir/mangowm-session.target.wants/noctalia.service" \
    >/dev/null 2>&1 || true
}

sync_existing_config_into_repo() {
  local timestamp backup_dir

  if run_as_user test -d "$noctalia_config_dir" && ! run_as_user test -L "$noctalia_config_dir"; then
    if command -v rsync >/dev/null 2>&1; then
      run_as_user rsync -a "$noctalia_config_dir/." "$noctalia_template_dir/"
    else
      run_as_user cp -a "$noctalia_config_dir/." "$noctalia_template_dir/"
    fi

    timestamp="$(date +%Y%m%d-%H%M%S)"
    backup_dir="${noctalia_backup_root}/config-${timestamp}"
    run_as_user mkdir -p "$noctalia_backup_root"
    run_as_user mv "$noctalia_config_dir" "$backup_dir"
  elif run_as_user test -e "$noctalia_config_dir" && ! run_as_user test -L "$noctalia_config_dir"; then
    timestamp="$(date +%Y%m%d-%H%M%S)"
    backup_dir="${noctalia_backup_root}/path-${timestamp}"
    run_as_user mkdir -p "$noctalia_backup_root"
    run_as_user mv "$noctalia_config_dir" "$backup_dir"
  fi
}

ensure_symlinked_config() {
  run_as_user mkdir -p "$(dirname "$noctalia_config_dir")"
  run_as_user ln -sfn "$noctalia_template_dir" "$noctalia_config_dir"
}

sync_existing_config_into_repo
if [[ -x "$render_workspace_meta_script" ]]; then
  run_as_user "$render_workspace_meta_script"
fi
ensure_symlinked_config
cleanup_legacy_noctalia_wants

if command -v systemctl >/dev/null 2>&1; then
  run_as_user systemctl --user daemon-reload >/dev/null 2>&1 || true
  if ! run_as_user systemctl --user is-enabled noctalia.service >/dev/null 2>&1; then
    run_as_user systemctl --user enable noctalia.service >/dev/null 2>&1 || true
  fi
  if run_as_user systemctl --user is-active noctalia.service >/dev/null 2>&1; then
    run_as_user systemctl --user try-restart noctalia.service >/dev/null 2>&1 || true
  fi
fi
