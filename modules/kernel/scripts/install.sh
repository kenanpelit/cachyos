#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
MODS_SRC="${SCRIPT_DIR}/../dotfiles/modules-load.d/99-kernel.conf"
TP_SRC="${SCRIPT_DIR}/../dotfiles/modprobe.d/thinkpad.conf"
BL_SRC="${SCRIPT_DIR}/../dotfiles/modprobe.d/blacklist-kernel.conf"

MODS_DST="/etc/modules-load.d/99-kernel.conf"
TP_DST="/etc/modprobe.d/thinkpad.conf"
BL_DST="/etc/modprobe.d/blacklist-kernel.conf"

SUDO=""
if [ "$(id -u)" -ne 0 ]; then
  if ! command -v sudo >/dev/null 2>&1; then
    echo "sudo is required to install kernel configs" >&2
    exit 1
  fi
  SUDO="sudo"
fi

install_if_changed() {
  local src="$1" dst="$2"
  if [ -f "${dst}" ] && cmp -s "${src}" "${dst}"; then
    return 0
  fi
  ${SUDO} install -m 644 "${src}" "${dst}"
}

install_if_changed "${MODS_SRC}" "${MODS_DST}"
install_if_changed "${TP_SRC}" "${TP_DST}"
install_if_changed "${BL_SRC}" "${BL_DST}"

apply_grub_cmdline() {
  local grub_default="/etc/default/grub"
  [ -f "${grub_default}" ] || return 0

  local params=(
    "intel_pstate=active"
    "intel_idle.max_cstate=7"
    "processor.ignore_ppc=1"
    "i915.enable_guc=3"
    "i915.enable_fbc=1"
    "i915.enable_dc=2"
    "i915.enable_psr=1"
    "i915.fastboot=1"
    "mem_sleep_default=s2idle"
  )

  local current line changed=0
  line="$(${SUDO} awk -F= '/^GRUB_CMDLINE_LINUX_DEFAULT=/{print $0}' "${grub_default}" || true)"
  if [ -z "${line}" ]; then
    current=""
  else
    current="${line#GRUB_CMDLINE_LINUX_DEFAULT=}"
    current="${current%\"}"
    current="${current#\"}"
  fi

  for p in "${params[@]}"; do
    if ! grep -qw -- "${p}" <<<"${current}"; then
      current="${current} ${p}"
      changed=1
    fi
  done

  current="$(echo "${current}" | xargs)"

  if [ "${changed}" -eq 1 ]; then
    if [ -z "${line}" ]; then
      echo "GRUB_CMDLINE_LINUX_DEFAULT=\"${current}\"" | ${SUDO} tee -a "${grub_default}" >/dev/null
    else
      ${SUDO} sed -i -E "s|^GRUB_CMDLINE_LINUX_DEFAULT=.*|GRUB_CMDLINE_LINUX_DEFAULT=\"${current}\"|" "${grub_default}"
    fi

    if command -v grub-mkconfig >/dev/null 2>&1; then
      ${SUDO} grub-mkconfig -o /boot/grub/grub.cfg
    else
      echo "grub-mkconfig not found; update GRUB config manually." >&2
    fi
  fi
}

apply_grub_cmdline
