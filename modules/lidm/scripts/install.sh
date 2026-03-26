#!/usr/bin/env bash
set -euo pipefail

SUDO=""
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
KEYMAP_DROPIN_SRC="${SCRIPT_DIR}/../dotfiles/systemd/system/lidm.service.d/10-vconsole-keymap.conf"
KEYMAP_DROPIN_DST="/etc/systemd/system/lidm.service.d/10-vconsole-keymap.conf"

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

install_root_file_if_changed() {
  local src="$1"
  local dst="$2"
  local mode="$3"

  run_root install -d "$(dirname "${dst}")"

  if run_root test -f "${dst}" && run_root cmp -s "${src}" "${dst}"; then
    return 0
  fi

  run_root install -m "${mode}" "${src}" "${dst}"
}

echo "==> LiDM display manager setup"

disable_unit_if_exists gdm.service
disable_unit_if_exists greetd.service
disable_unit_if_exists sddm.service
disable_unit_if_exists lightdm.service
disable_unit_if_exists lxdm.service
disable_unit_if_exists ly.service
disable_unit_if_exists emptty.service

if ! run_root systemctl list-unit-files lidm.service >/dev/null 2>&1; then
  echo "lidm.service not found. Install LiDM and its systemd service package first." >&2
  exit 1
fi

install_root_file_if_changed "${KEYMAP_DROPIN_SRC}" "${KEYMAP_DROPIN_DST}" 644

run_root systemctl daemon-reload
run_root systemctl unmask lidm.service >/dev/null 2>&1 || true
run_root systemctl enable lidm.service >/dev/null 2>&1 || run_root systemctl enable --force lidm.service >/dev/null 2>&1

echo "Done."
echo "Enabled: lidm.service"
echo "Installed: lidm.service keymap preload drop-in"
echo "Disabled (if present): gdm, greetd, sddm, lightdm, lxdm, ly, emptty"
echo "Session wrappers and desktop entries are provided by the sessions module."
echo
echo "Apply now or reboot:"
echo "  sudo systemctl start lidm"
