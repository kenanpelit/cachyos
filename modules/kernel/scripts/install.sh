#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
MODS_SRC="${SCRIPT_DIR}/../dotfiles/modules-load.d/99-kernel.conf"
TP_SRC="${SCRIPT_DIR}/../dotfiles/modprobe.d/thinkpad.conf"
BL_SRC="${SCRIPT_DIR}/../dotfiles/modprobe.d/blacklist-kernel.conf"
I915_SRC="${SCRIPT_DIR}/../dotfiles/modprobe.d/i915-intel-gpu.conf"

MODS_DST="/etc/modules-load.d/99-kernel.conf"
TP_DST="/etc/modprobe.d/thinkpad.conf"
BL_DST="/etc/modprobe.d/blacklist-kernel.conf"
I915_DST="/etc/modprobe.d/i915-intel-gpu.conf"

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
install_if_changed "${I915_SRC}" "${I915_DST}"

strip_shell_quotes() {
  local value="$1"
  if [[ "${value}" == \"*\" && "${value}" == *\" ]]; then
    value="${value#\"}"
    value="${value%\"}"
  elif [[ "${value}" == \'*\' && "${value}" == *\' ]]; then
    value="${value#\'}"
    value="${value%\'}"
  fi
  printf '%s\n' "${value}"
}

upsert_kernel_param() {
  local current="$1" key="$2" value="$3"
  local token filtered=()
  local target="${key}=${value}"

  for token in ${current}; do
    if [[ "${token}" == "${key}" || "${token}" == "${key}="* ]]; then
      continue
    fi
    filtered+=("${token}")
  done

  filtered+=("${target}")
  printf '%s\n' "${filtered[*]}"
}

remove_kernel_param() {
  local current="$1" key="$2"
  local token filtered=()

  for token in ${current}; do
    if [[ "${token}" == "${key}" || "${token}" == "${key}="* ]]; then
      continue
    fi
    filtered+=("${token}")
  done

  printf '%s\n' "${filtered[*]}"
}

apply_grub_cmdline() {
  local grub_default="/etc/default/grub"
  [ -f "${grub_default}" ] || return 0

  local params=(
    "intel_pstate active"
    "intel_idle.max_cstate 7"
    "processor.ignore_ppc 1"
    "i915.enable_guc 3"
    "i915.enable_fbc 1"
    "i915.enable_dc 0"
    "i915.enable_psr 0"
    "mem_sleep_default s2idle"
  )
  local managed_keys=(
    "intel_pstate"
    "intel_idle.max_cstate"
    "processor.ignore_ppc"
    "i915.enable_guc"
    "i915.enable_fbc"
    "i915.enable_dc"
    "i915.enable_psr"
    "i915.fastboot"
    "mem_sleep_default"
  )

  local current original line changed=0 param key value managed_key
  line="$(${SUDO} awk -F= '/^GRUB_CMDLINE_LINUX_DEFAULT=/{print $0}' "${grub_default}" || true)"
  if [ -z "${line}" ]; then
    current=""
  else
    current="${line#GRUB_CMDLINE_LINUX_DEFAULT=}"
    current="$(strip_shell_quotes "${current}")"
  fi
  original="${current}"

  for managed_key in "${managed_keys[@]}"; do
    current="$(remove_kernel_param "${current}" "${managed_key}")"
  done

  for param in "${params[@]}"; do
    key="${param%% *}"
    value="${param#* }"
    current="$(upsert_kernel_param "${current}" "${key}" "${value}")"
  done

  current="$(echo "${current}" | xargs)"

  if [[ "${current}" != "${original}" ]]; then
    changed=1
  fi

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
