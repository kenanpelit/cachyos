#!/usr/bin/env bash
# ==============================================================================
# Script: osc-tty-launcher.sh
# Description: UWSM-aware interactive TTY launcher for the Margo desktop and VM profiles
# Usage: osc-tty-launcher [auto-tty [VT]] | [margo|vmubuntu|vmarch|vmcachy|vmnixos]
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

# Margo route — prefers the session wrapper that already chains
# margo-session → start-margo → margo. Wrapper handles env setup
# (XDG_*, GTK/QT theme, icon theme, …) and uwsm start invocation.
launch_margo() {
  local wrapper_cmd
  wrapper_cmd="$(resolve_cmd "${HOME}/.local/bin/margo-uwsm-session" "margo-uwsm-session" 2>/dev/null || true)"

  if command -v margo-session >/dev/null 2>&1; then
    run_uwsm_route "margo-session" "${wrapper_cmd}" margo-session
  fi
  if command -v start-margo >/dev/null 2>&1; then
    run_uwsm_route "start-margo" "${wrapper_cmd}" start-margo
  fi
  run_uwsm_route "margo" "${wrapper_cmd}" margo
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
  1) Margo     (UWSM)
  2) Ubuntu VM (Sway qemu_vmubuntu)
  3) Arch VM   (Sway qemu_vmarch)
  4) Cachy VM  (Sway qemu_vmcachy)
  5) NixOS VM  (Sway qemu_vmnixos)
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

  Autostart route:
    tty2   -> Margo (UWSM)
    others -> manual (this launcher)

  Manual commands:
    exec osc-tty-launcher
    exec osc-tty-launcher margo
    exec osc-tty-launcher vmubuntu

  Route menu:
    1) Margo     (UWSM)
    2) Ubuntu VM
    3) Arch VM
    4) Cachy VM
    5) NixOS VM

  Next step:
    Type: exec osc-tty-launcher
EOF
}

handle_auto_tty() {
  local tty="${1:-${XDG_VTNR:-}}"

  case "${tty}" in
    2)
      echo "TTY2: launching Margo via UWSM"
      launch_margo
      ;;
    *)
      show_tty_hints "${tty}"
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
    margo)
      launch_margo
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
      launch_margo
      ;;
    2)
      run_vm_via_sway_profile "qemu_vmubuntu" "${SVM_UBUNTU_CMD}"
      ;;
    3)
      run_vm_via_sway_profile "qemu_vmarch" "${SVM_ARCH_CMD}"
      ;;
    4)
      run_vm_via_sway_profile "qemu_vmcachy" "${SVM_CACHY_CMD}"
      ;;
    5)
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
