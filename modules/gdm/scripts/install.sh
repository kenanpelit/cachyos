#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
MODULES_DIR="$(cd -- "${SCRIPT_DIR}/../.." && pwd)"
WAYLAND_SESSIONS_DIR="/usr/share/wayland-sessions"

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

disable_unit_if_exists() {
  local unit="$1"
  if run_root systemctl list-unit-files "${unit}" >/dev/null 2>&1; then
    run_root systemctl disable "${unit}" >/dev/null 2>&1 || true
  fi
}

install_session_file() {
  local src="$1"
  local label="$2"

  if [ ! -f "${src}" ]; then
    echo "Warning: ${label} session file not found: ${src}" >&2
    return 0
  fi

  run_root install -d -m 755 "${WAYLAND_SESSIONS_DIR}"
  run_root install -m 644 "${src}" "${WAYLAND_SESSIONS_DIR}/$(basename "${src}")"
}

echo "==> GDM display manager setup"

# Keep only one display manager enabled.
disable_unit_if_exists greetd.service
disable_unit_if_exists sddm.service
disable_unit_if_exists lightdm.service
disable_unit_if_exists lxdm.service
disable_unit_if_exists ly.service

if ! run_root systemctl list-unit-files gdm.service >/dev/null 2>&1; then
  echo "gdm.service not found. Install package 'gdm' first." >&2
  exit 1
fi

# Install optimized Wayland sessions for GDM chooser.
install_session_file "${MODULES_DIR}/sessions/dotfiles/niri-optimized.desktop" "Niri (Optimized)"
install_session_file "${MODULES_DIR}/sessions/dotfiles/gnome-optimized.desktop" "GNOME (Optimized)"
install_session_file "${MODULES_DIR}/hyprland/dotfiles/hyprland-optimized.desktop" "Hyprland (Optimized)"

run_root systemctl daemon-reload
run_root systemctl unmask gdm.service >/dev/null 2>&1 || true
run_root systemctl enable gdm.service >/dev/null 2>&1 || run_root systemctl enable --force gdm.service >/dev/null 2>&1

echo "Done."
echo "Enabled: gdm.service"
echo "Disabled (if present): greetd, sddm, lightdm, lxdm, ly"
echo "Installed Wayland sessions: niri-optimized, hyprland-optimized, gnome-optimized"
echo
echo "Apply now or reboot:"
echo "  sudo systemctl start gdm"
