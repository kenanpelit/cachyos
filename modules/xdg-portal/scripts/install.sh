#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
source "$REPO_ROOT/modules/base/lib/core.sh"

if ! command -v systemctl >/dev/null 2>&1; then
  exit 0
fi

user_systemd_dir="$USER_HOME/.config/systemd/user"
user_dbus_service_dir="$USER_HOME/.local/share/dbus-1/services"
timer_unit="$REPO_ROOT/modules/xdg-portal/dotfiles/systemd/user/xdg-desktop-portal-delayed.timer"
service_unit="$REPO_ROOT/modules/xdg-portal/dotfiles/systemd/user/xdg-desktop-portal-delayed.service"

ensure_user_link() {
  local src="$1"
  local dst="$2"
  local current=""

  current="$(run_as_user readlink "$dst" 2>/dev/null || true)"
  if [[ "$current" != "$src" ]]; then
    run_as_user ln -sfn "$src" "$dst"
  fi
}

cleanup_user_dbus_service() {
  local service_name="$1"
  run_as_user rm -f "$user_dbus_service_dir/$service_name" >/dev/null 2>&1 || true
}

run_as_user mkdir -p "$user_systemd_dir"
ensure_user_link "$timer_unit" "$user_systemd_dir/xdg-desktop-portal-delayed.timer"
ensure_user_link "$service_unit" "$user_systemd_dir/xdg-desktop-portal-delayed.service"

# Retire stale user-level D-Bus service overrides. The vendor service files are
# authoritative; local copies only add duplicate-provider noise at session boot.
cleanup_user_dbus_service org.gnome.Settings.GlobalShortcutsProvider.service
cleanup_user_dbus_service org.freedesktop.FileManager1.service
cleanup_user_dbus_service org.Nemo.service

run_as_user systemctl --user daemon-reload >/dev/null 2>&1 || true

# Refresh the timer links so delayed portal orchestration follows compositor
# session targets instead of default.target.
run_as_user systemctl --user disable --now xdg-desktop-portal-delayed.timer xdg-desktop-portal-delayed.service >/dev/null 2>&1 || true
run_as_user systemctl --user stop xdg-desktop-portal-delayed.service >/dev/null 2>&1 || true
run_as_user rm -f "$USER_HOME/.config/systemd/user/default.target.wants/xdg-desktop-portal-delayed.timer" || true
run_as_user rm -f "$USER_HOME/.config/systemd/user/default.target.wants/xdg-desktop-portal-delayed.service" || true
run_as_user rm -f "$USER_HOME/.config/systemd/user/graphical-session.target.wants/xdg-desktop-portal-delayed.timer" || true
run_as_user rm -f "$USER_HOME/.config/systemd/user/graphical-session.target.wants/xdg-desktop-portal-delayed.service" || true
run_as_user systemctl --user enable xdg-desktop-portal-delayed.timer >/dev/null 2>&1 || true
run_as_user systemctl --user start xdg-desktop-portal-delayed.timer >/dev/null 2>&1 || true
