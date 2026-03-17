#!/usr/bin/env bash
# ==============================================================================
# Script: osc-tty-launcher.sh
# Description: UWSM-aware interactive TTY launcher for desktop routes and VM profiles
# Usage: osc-tty-launcher [auto-tty [VT]] | [niri|hyprland|gnome|vmubuntu|vmarch|vmcachy|vmnixos]
# ==============================================================================
set -euo pipefail

SCRIPT_NAME="$(basename "$0")"

resolve_cmd() {
  local preferred="$1"
  local fallback="$2"
  if [[ -n "$preferred" && -x "$preferred" ]]; then
    printf '%s\n' "$preferred"
    return 0
  fi
  if command -v "$fallback" >/dev/null 2>&1; then
    command -v "$fallback"
    return 0
  fi
  return 1
}

GNOME_TTY_CMD="$(resolve_cmd "${HOME}/.local/bin/gnome_tty" "gnome_tty" 2>/dev/null || true)"

SVM_UBUNTU_CMD="$(resolve_cmd "${HOME}/.local/bin/svmubuntu" "svmubuntu" 2>/dev/null || true)"
SVM_ARCH_CMD="$(resolve_cmd "${HOME}/.local/bin/svmarch" "svmarch" 2>/dev/null || true)"
SVM_CACHY_CMD="$(resolve_cmd "${HOME}/.local/bin/svmcachy" "svmcachy" 2>/dev/null || true)"
SVM_NIXOS_CMD="$(resolve_cmd "${HOME}/.local/bin/svmnixos" "svmnixos" 2>/dev/null || true)"

ensure_runtime_environment() {
  local uid
  uid="$(id -u)"

  export OSC_TTY_LAUNCHER_GUARD=1
  export SYSTEMD_OFFLINE=0
  export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/${uid}}"
  export XDG_SESSION_TYPE="${XDG_SESSION_TYPE:-wayland}"
}

run_uwsm_route() {
  local wrapper_cmd="$2"
  local uwsm_cmd="$1"
  shift 2
  local -a fallback_cmd=("$@")

  ensure_runtime_environment

  if [[ -n "${wrapper_cmd}" ]]; then
    exec "${wrapper_cmd}"
  fi

  if command -v uwsm >/dev/null 2>&1; then
    exec uwsm start -- "${uwsm_cmd}"
  fi

  if [[ ${#fallback_cmd[@]} -gt 0 ]]; then
    exec "${fallback_cmd[@]}"
  fi

  echo "[${SCRIPT_NAME}] route unavailable: ${uwsm_cmd}" >&2
  exit 1
}

launch_niri() {
  local wrapper_cmd
  wrapper_cmd="$(resolve_cmd "${HOME}/.local/bin/niri-uwsm-session" "niri-uwsm-session" 2>/dev/null || true)"

  if command -v niri-session >/dev/null 2>&1; then
    run_uwsm_route "niri-session" "${wrapper_cmd}" niri-session
  fi

  run_uwsm_route "niri" "${wrapper_cmd}" niri --session
}

launch_hyprland() {
  local wrapper_cmd
  wrapper_cmd="$(resolve_cmd "${HOME}/.local/bin/hyprland-uwsm-session" "hyprland-uwsm-session" 2>/dev/null || true)"

  if command -v start-hyprland >/dev/null 2>&1; then
    run_uwsm_route "start-hyprland" "${wrapper_cmd}" start-hyprland
  fi

  run_uwsm_route "Hyprland" "${wrapper_cmd}" Hyprland
}

launch_gnome() {
  ensure_runtime_environment

  export GNOME_TTY_GUARD=1
  export GNOME_TTY_GUARD_FILE="${XDG_RUNTIME_DIR}/gnome-tty.guard"

  if [[ -n "${GNOME_TTY_CMD}" ]]; then
    exec "${GNOME_TTY_CMD}"
  fi

  exec gnome-session --session=gnome --no-reexec
}

run_vm_via_sway_profile() {
  local profile="$1"
  local fallback_cmd="$2"
  local cfg="${HOME}/.config/sway/${profile}"

  ensure_runtime_environment
  unset XDG_CURRENT_DESKTOP XDG_SESSION_DESKTOP DESKTOP_SESSION
  export XDG_SESSION_TYPE=wayland
  export XDG_SESSION_DESKTOP=sway
  export XDG_CURRENT_DESKTOP=sway
  export DESKTOP_SESSION=sway

  if [[ -f "$cfg" ]]; then
    exec sway -c "$cfg"
  fi

  if [[ -n "$fallback_cmd" ]]; then
    exec "$fallback_cmd" start --gtk-gl off
  fi

  echo "[${SCRIPT_NAME}] VM route unavailable: ${profile}" >&2
  exit 1
}

show_menu() {
  cat <<'EOF'
=========================================
  TTY Launcher (UWSM-aware)
=========================================
  1) Niri (UWSM)
  2) Hyprland (UWSM)
  3) GNOME
  4) Ubuntu VM (Sway qemu_vmubuntu)
  5) Arch VM   (Sway qemu_vmarch)
  6) Cachy VM  (Sway qemu_vmcachy)
  7) NixOS VM  (Sway qemu_vmnixos)
  q) Exit
EOF
}

clear_if_interactive_tty() {
  if [[ -t 1 ]]; then
    command -v clear >/dev/null 2>&1 && clear || printf '\033c'
  fi
}

show_tty_hints() {
  local tty="${1:-${XDG_VTNR:-?}}"

  clear_if_interactive_tty

  cat <<EOF
=========================================
  TTY Launcher
=========================================
  Current TTY: ${tty}

  Quick routes:
    tty2 -> Niri (UWSM)
    tty3 -> Hyprland (UWSM)
    tty4 -> GNOME
    tty5 -> Ubuntu VM via Sway
    tty6 -> manual launcher

  Manual commands:
    exec osc-tty-launcher
    exec osc-tty-launcher niri
    exec osc-tty-launcher hyprland
    exec osc-tty-launcher gnome

  Route menu:
    1) Niri (UWSM)
    2) Hyprland (UWSM)
    3) GNOME
    4) Ubuntu VM
    5) Arch VM
    6) Cachy VM
    7) NixOS VM

  Next step:
    Type: exec osc-tty-launcher
EOF
}

handle_auto_tty() {
  local tty="${1:-${XDG_VTNR:-}}"

  case "${tty}" in
    1)
      show_tty_hints "${tty}"
      ;;
    2)
      echo "TTY2: launching Niri via UWSM"
      launch_niri
      ;;
    3)
      echo "TTY3: launching Hyprland via UWSM"
      launch_hyprland
      ;;
    4)
      echo "TTY4: launching GNOME"
      launch_gnome
      ;;
    5)
      echo "TTY5: launching Ubuntu VM profile in Sway"
      run_vm_via_sway_profile "qemu_vmubuntu" "${SVM_UBUNTU_CMD}"
      ;;
    6)
      show_tty_hints "${tty}"
      ;;
    *)
      echo "[${SCRIPT_NAME}] no autostart route configured for tty ${tty}" >&2
      return 1
      ;;
  esac
}

main() {
  case "${1:-}" in
    auto-tty)
      shift
      handle_auto_tty "${1:-}"
      exit 0
      ;;
    niri)
      launch_niri
      ;;
    hyprland)
      launch_hyprland
      ;;
    gnome)
      launch_gnome
      ;;
    vmubuntu)
      run_vm_via_sway_profile "qemu_vmubuntu" "${SVM_UBUNTU_CMD}"
      ;;
    vmarch)
      run_vm_via_sway_profile "qemu_vmarch" "${SVM_ARCH_CMD}"
      ;;
    vmcachy)
      run_vm_via_sway_profile "qemu_vmcachy" "${SVM_CACHY_CMD}"
      ;;
    vmnixos)
      run_vm_via_sway_profile "qemu_vmnixos" "${SVM_NIXOS_CMD}"
      ;;
    -h|--help|help)
      show_tty_hints "${XDG_VTNR:-?}"
      exit 0
      ;;
  esac

  while true; do
    show_menu
    printf 'Select route: '
    read -r choice

    case "$choice" in
    1)
      launch_niri
      ;;
    2)
      launch_hyprland
      ;;
    3)
      launch_gnome
      ;;
    4)
      run_vm_via_sway_profile "qemu_vmubuntu" "${SVM_UBUNTU_CMD}"
      ;;
    5)
      run_vm_via_sway_profile "qemu_vmarch" "${SVM_ARCH_CMD}"
      ;;
    6)
      run_vm_via_sway_profile "qemu_vmcachy" "${SVM_CACHY_CMD}"
      ;;
    7)
      run_vm_via_sway_profile "qemu_vmnixos" "${SVM_NIXOS_CMD}"
      ;;
    q | Q)
      exit 0
      ;;
    *)
      echo "Invalid choice: ${choice}" >&2
      ;;
    esac
  done
}

main "$@"
