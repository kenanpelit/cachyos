#!/usr/bin/env bash
set -euo pipefail

SUDO=""
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_SRC="${SCRIPT_DIR}/../dotfiles/lemurs/config.toml"
CONFIG_DST="/etc/lemurs/config.toml"
VARIABLES_SRC="${SCRIPT_DIR}/../dotfiles/lemurs/variables.toml"
VARIABLES_DST="/etc/lemurs/variables.toml"
XSETUP_SRC="${SCRIPT_DIR}/../dotfiles/lemurs/xsetup.sh"
XSETUP_DST="/etc/lemurs/xsetup.sh"
TTY_DROPIN_SRC="${SCRIPT_DIR}/../dotfiles/systemd/system/lemurs.service.d/10-tty7.conf"
TTY_DROPIN_DST="/etc/systemd/system/lemurs.service.d/10-tty7.conf"
KEYMAP_DROPIN_SRC="${SCRIPT_DIR}/../dotfiles/systemd/system/lemurs.service.d/10-vconsole-keymap.conf"
KEYMAP_DROPIN_DST="/etc/systemd/system/lemurs.service.d/10-vconsole-keymap.conf"

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

echo "==> Lemurs display manager setup"

disable_unit_if_exists gdm.service
disable_unit_if_exists greetd.service
disable_unit_if_exists sddm.service
disable_unit_if_exists lightdm.service
disable_unit_if_exists lxdm.service
disable_unit_if_exists lidm.service
disable_unit_if_exists ly.service
disable_unit_if_exists emptty.service

if ! run_root systemctl list-unit-files lemurs.service >/dev/null 2>&1; then
  echo "lemurs.service not found. Install package 'lemurs-git' first." >&2
  exit 1
fi

run_root install -d /etc/lemurs /etc/lemurs/wms /etc/lemurs/wayland

install_root_file_if_changed "${CONFIG_SRC}" "${CONFIG_DST}" 644
install_root_file_if_changed "${VARIABLES_SRC}" "${VARIABLES_DST}" 644
install_root_file_if_changed "${XSETUP_SRC}" "${XSETUP_DST}" 755
install_root_file_if_changed "${TTY_DROPIN_SRC}" "${TTY_DROPIN_DST}" 644
install_root_file_if_changed "${KEYMAP_DROPIN_SRC}" "${KEYMAP_DROPIN_DST}" 644

run_root systemctl daemon-reload
run_root systemctl unmask lemurs.service >/dev/null 2>&1 || true
run_root systemctl enable lemurs.service >/dev/null 2>&1 || run_root systemctl enable --force lemurs.service >/dev/null 2>&1

echo "Done."
echo "Enabled: lemurs.service"
echo "Installed: /etc/lemurs/config.toml"
echo "Installed: /etc/lemurs/variables.toml"
echo "Installed: /etc/lemurs/xsetup.sh"
echo "Installed: lemurs.service tty/keymap drop-ins"
echo "Disabled (if present): gdm, greetd, sddm, lightdm, lxdm, lidm, ly, emptty"
echo "Wayland session entries are provided by the sessions module."
echo "Custom sessions can be added under /etc/lemurs/wms and /etc/lemurs/wayland."
echo
echo "Apply now or reboot:"
echo "  sudo systemctl start lemurs"
