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

# Quickshell QML override tree for noctalia-shell. Quickshell loads
# the FIRST `<xdg-config-dir>/quickshell/noctalia-shell/shell.qml` it
# finds, so populating ~/.config/quickshell/noctalia-shell wins over
# /etc/xdg. We mirror the system tree as symlinks (so noctalia-shell-git
# package updates are picked up automatically) and replace just the
# files we need to patch with cachy-managed real copies.
qs_overrides_dir="$MODULE_DIR/dotfiles/quickshell-overrides/noctalia-shell"
qs_system_dir="/etc/xdg/quickshell/noctalia-shell"
qs_user_dir="$USER_HOME/.config/quickshell/noctalia-shell"

cleanup_legacy_noctalia_wants() {
  run_as_user rm -f \
    "$user_systemd_dir/default.target.wants/noctalia.service" \
    "$user_systemd_dir/graphical-session.target.wants/noctalia.service" \
    "$user_systemd_dir/hyprland-session.target.wants/noctalia.service" \
    "$user_systemd_dir/niri-session.target.wants/noctalia.service" \
    "$user_systemd_dir/mangowm-session.target.wants/noctalia.service" \
    "$user_systemd_dir/margo-session.target.wants/noctalia.service" \
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

# Mirror /etc/xdg/quickshell/noctalia-shell/ into the user's XDG config
# as symlinks, then replace each file under $qs_overrides_dir with a real
# copy so QML changes managed by cachy take precedence. Files removed
# from the override tree go back to whatever /etc/xdg has, since the
# mirror is rebuilt every install.
ensure_quickshell_overrides() {
  if [[ ! -d "$qs_overrides_dir" ]]; then
    return 0
  fi
  if [[ ! -d "$qs_system_dir" ]]; then
    return 0
  fi

  run_as_user mkdir -p "$(dirname "$qs_user_dir")"

  # Wipe and rebuild the user dir each time so:
  #   1. removing a file from the cachy override tree falls back to the
  #      system version on the next install (no stale overrides);
  #   2. files added by a noctalia-shell-git update are picked up
  #      without manual re-sync.
  run_as_user rm -rf "$qs_user_dir"
  run_as_user mkdir -p "$qs_user_dir"

  # Pass 1: every file in /etc/xdg becomes a same-relative-path symlink.
  run_as_user bash -c '
    set -euo pipefail
    src="$1"
    dst="$2"
    cd "$src"
    find . -type d -print0 | xargs -0 -I{} mkdir -p "$dst/{}"
    find . \( -type f -o -type l \) -print0 | while IFS= read -r -d "" f; do
      ln -sfn "$src/$f" "$dst/$f"
    done
  ' _ "$qs_system_dir" "$qs_user_dir"

  # Pass 2: every file under the cachy overrides tree replaces the
  # symlink with a real copy (install -m 644 derefs cleanly).
  run_as_user bash -c '
    set -euo pipefail
    src="$1"
    dst="$2"
    cd "$src"
    find . \( -type f -o -type l \) -print0 | while IFS= read -r -d "" f; do
      install -Dm644 "$src/$f" "$dst/$f"
    done
  ' _ "$qs_overrides_dir" "$qs_user_dir"
}

sync_existing_config_into_repo
if [[ -x "$render_workspace_meta_script" ]]; then
  run_as_user "$render_workspace_meta_script"
fi
ensure_symlinked_config
ensure_quickshell_overrides
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
