#!/usr/bin/env bash
set -euo pipefail

# -----------------------------------------------------------------------------
# osc-tty-launcher
# -----------------------------------------------------------------------------
# Purpose:
# - Interactive TTY launcher for desktop routes and VM profiles.
# - VM routes prefer Sway profile configs (qemu_vm*) to avoid GTK init issues
#   that can happen when launching QEMU GTK directly from a raw TTY context.
# -----------------------------------------------------------------------------

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

NIRI_TTY_CMD="niri --session"
if command -v niri-session >/dev/null 2>&1; then
  NIRI_TTY_CMD="niri-session"
fi

HYPR_OSC_CMD="$(resolve_cmd "${HOME}/.local/bin/hypr-osc" "hypr-osc" 2>/dev/null || true)"
GNOME_TTY_CMD="$(resolve_cmd "${HOME}/.local/bin/gnome_tty" "gnome_tty" 2>/dev/null || true)"

SVM_UBUNTU_CMD="$(resolve_cmd "${HOME}/.local/bin/svmubuntu" "svmubuntu" 2>/dev/null || true)"
SVM_ARCH_CMD="$(resolve_cmd "${HOME}/.local/bin/svmarch" "svmarch" 2>/dev/null || true)"
SVM_CACHY_CMD="$(resolve_cmd "${HOME}/.local/bin/svmcachy" "svmcachy" 2>/dev/null || true)"
SVM_NIXOS_CMD="$(resolve_cmd "${HOME}/.local/bin/svmnixos" "svmnixos" 2>/dev/null || true)"

run_vm_via_sway_profile() {
  local profile="$1"
  local fallback_cmd="$2"
  local cfg="${HOME}/.config/sway/${profile}"

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
  TTY Launcher
=========================================
  1) Niri
  2) Hyprland
  3) GNOME
  4) Ubuntu VM (Sway qemu_vmubuntu)
  5) Arch VM   (Sway qemu_vmarch)
  6) Cachy VM  (Sway qemu_vmcachy)
  7) NixOS VM  (Sway qemu_vmnixos)
  q) Exit
EOF
}

main() {
  while true; do
    show_menu
    printf 'Select route: '
    read -r choice

    case "$choice" in
    1)
      exec ${NIRI_TTY_CMD}
      ;;
    2)
      if [[ -n "${HYPR_OSC_CMD}" ]]; then
        exec "${HYPR_OSC_CMD}" tty
      fi
      exec Hyprland
      ;;
    3)
      if [[ -n "${GNOME_TTY_CMD}" ]]; then
        exec "${GNOME_TTY_CMD}"
      fi
      exec gnome-session --session=gnome --no-reexec
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
