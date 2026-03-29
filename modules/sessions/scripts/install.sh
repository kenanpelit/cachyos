#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
DOTFILES_DIR="${SCRIPT_DIR}/../dotfiles"
WAYLAND_SESSIONS_DIR="/usr/share/wayland-sessions"
LOCAL_BIN_DIR="/usr/local/bin"

# shellcheck source=/dev/null
source "$REPO_ROOT/modules/base/lib/core.sh"

USER_WAYLAND_SESSIONS_DIR="${USER_HOME}/.local/share/wayland-sessions"

SUDO=""
if [ "$(id -u)" -ne 0 ]; then
  if ! command -v sudo >/dev/null 2>&1; then
    echo "sudo is required" >&2
    exit 1
  fi
  SUDO="sudo"
fi

run_root() {
  if [ -n "${SUDO}" ]; then
    "${SUDO}" "$@"
  else
    "$@"
  fi
}

install_session() {
  local src="$1"
  local label="$2"
  if [ -f "$src" ]; then
    echo "Installing ${label} to ${WAYLAND_SESSIONS_DIR}..."
    run_root install -d -m 755 "${WAYLAND_SESSIONS_DIR}"
    run_root install -m 644 "$src" "${WAYLAND_SESSIONS_DIR}/$(basename "$src")"
  else
    echo "Warning: $src not found, skipping ${label}." >&2
  fi
}

install_wrapper() {
  local src="$1"
  local dst_name="$2"
  if [ -f "$src" ]; then
    run_root install -d -m 755 "${LOCAL_BIN_DIR}"
    run_root install -m 755 "$src" "${LOCAL_BIN_DIR}/${dst_name}"
  else
    echo "Warning: wrapper not found: $src" >&2
  fi
}

remove_session() {
  local name="$1"
  local target="${WAYLAND_SESSIONS_DIR}/${name}"
  if [ -e "$target" ] || [ -L "$target" ]; then
    echo "Removing legacy session ${target}..."
    run_root rm -f "$target"
  fi
}

remove_user_session() {
  local name="$1"
  local target="${USER_WAYLAND_SESSIONS_DIR}/${name}"
  if [ -e "$target" ] || [ -L "$target" ]; then
    echo "Removing user session ${target}..."
    run_as_user rm -f "$target"
  fi
}

remove_wrapper() {
  local name="$1"
  local target="${LOCAL_BIN_DIR}/${name}"
  if [ -e "$target" ] || [ -L "$target" ]; then
    echo "Removing wrapper ${target}..."
    run_root rm -f "$target"
  fi
}

remove_session "niri.desktop"
remove_session "niri-optimized.desktop"
remove_session "hyprland.desktop"
remove_session "gnome-optimized.desktop"
remove_user_session "gnome-optimized.desktop"

install_session "${DOTFILES_DIR}/niri-uwsm.desktop" "Niri (UWSM)"
install_session "${DOTFILES_DIR}/hyprland-uwsm.desktop" "Hyprland (UWSM)"

install_wrapper "${DOTFILES_DIR}/niri-uwsm-session" "niri-uwsm-session"
install_wrapper "${DOTFILES_DIR}/hyprland-uwsm-session" "hyprland-uwsm-session"

run_root rm -f "${LOCAL_BIN_DIR}/niri-optimized-session"
remove_wrapper "gnome-optimized-session"

if command -v systemctl >/dev/null 2>&1; then
  user_systemd_dir="$USER_HOME/.config/systemd/user"

  run_as_user systemctl --user daemon-reload >/dev/null 2>&1 || true
  run_as_user rm -f "$user_systemd_dir/niri.service.d/10-session-bootstrap.conf" || true
  # Remove only legacy auto-start links. The units themselves are repo-managed
  # dotfiles, so disabling them on every sync just recreates the main symlinks.
  run_as_user rm -f \
    "$user_systemd_dir/default.target.wants/geoclue-agent.timer" \
    "$user_systemd_dir/default.target.wants/home-net-vpn.timer" \
    "$user_systemd_dir/default.target.wants/ppp-auto-profile.service" \
    "$user_systemd_dir/default.target.wants/ppp-auto-profile.timer" \
    "$user_systemd_dir/graphical-session.target.wants/geoclue-agent.timer" \
    "$user_systemd_dir/graphical-session.target.wants/geoclue-agent.service" \
    "$user_systemd_dir/graphical-session.target.wants/home-net-vpn.service" \
    "$user_systemd_dir/graphical-session.target.wants/ppp-auto-profile.service" \
    || true

  run_as_user systemctl --user disable --now geoclue-agent.timer >/dev/null 2>&1 || true

  if ! run_as_user systemctl --user is-enabled geoclue-agent.service >/dev/null 2>&1; then
    run_as_user systemctl --user enable geoclue-agent.service >/dev/null 2>&1 || true
  fi

  if run_as_user systemctl --user is-active graphical-session.target >/dev/null 2>&1; then
    run_as_user systemctl --user start geoclue-agent.service >/dev/null 2>&1 || true
  fi

  if ! run_as_user systemctl --user is-enabled home-net-vpn.timer >/dev/null 2>&1; then
    run_as_user systemctl --user enable --now home-net-vpn.timer >/dev/null 2>&1 || true
  fi

  if ! run_as_user systemctl --user is-enabled ppp-auto-profile.timer >/dev/null 2>&1; then
    run_as_user systemctl --user enable --now ppp-auto-profile.timer >/dev/null 2>&1 || true
  fi
fi

echo "Session installation complete."
