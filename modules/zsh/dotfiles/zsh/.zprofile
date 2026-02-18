# shellcheck shell=bash
# =============================================================================
# Multi-TTY desktop autostart router (login shell only)
# =============================================================================
# TTY1: display manager / manual launch info
# TTY2: Niri (niri-osc set tty)
# TTY3: Hyprland (hypr-set tty)
# TTY4: GNOME (gnome_tty)
# TTY5: Sway (Ubuntu VM profile)
# TTY6: manual
# =============================================================================

resolve_cmd() {
  local preferred="$1"
  local fallback_name="$2"

  if [[ -n "$preferred" && -x "$preferred" ]]; then
    printf '%s\n' "$preferred"
    return 0
  fi

  if command -v "$fallback_name" >/dev/null 2>&1; then
    command -v "$fallback_name"
    return 0
  fi

  return 1
}

is_login_shell=false
[[ $- == *l* ]] && is_login_shell=true

if $is_login_shell \
  && [[ -z "${WAYLAND_DISPLAY:-}" ]] \
  && [[ -z "${DISPLAY:-}" ]] \
  && [[ "${XDG_VTNR:-}" =~ ^[1-6]$ ]] \
  && [[ -z "${NIRI_TTY_GUARD:-}" ]] \
  && [[ -z "${GNOME_TTY_GUARD:-}" ]]; then

  # Avoid recursive autostart when desktop startup re-execs shell.
  if pgrep -x gnome-shell >/dev/null 2>&1 \
    || [[ -n "${GNOME_DESKTOP_SESSION_ID:-}" ]] \
    || [[ -n "${GNOME_SHELL_SESSION_MODE:-}" ]]; then
    return
  fi

  # TTY1 can already have an active session; do not interfere.
  if [[ "${XDG_VTNR}" == "1" && -n "${XDG_SESSION_TYPE:-}" ]]; then
    return
  fi

  uid="$(id -u)"
  export XDG_RUNTIME_DIR="/run/user/${uid}"

  NIRI_OSC_CMD="$(resolve_cmd "${HOME}/.local/bin/niri-osc" "niri-osc" 2>/dev/null || true)"
  HYPR_SET_CMD="$(resolve_cmd "${HOME}/.local/bin/hypr-set" "hypr-set" 2>/dev/null || true)"
  GNOME_TTY_CMD="$(resolve_cmd "${HOME}/.local/bin/gnome_tty" "gnome_tty" 2>/dev/null || true)"

  case "${XDG_VTNR}" in
    1)
      echo "TTY1: display manager / manual launch helper"
      echo "  Niri:     exec ${NIRI_OSC_CMD:-niri-osc} set tty"
      echo "  Hyprland: exec ${HYPR_SET_CMD:-hypr-set} tty"
      echo "  GNOME:    exec ${GNOME_TTY_CMD:-gnome_tty}"
      ;;

    2)
      echo "TTY2: launching Niri via niri-osc set tty"
      export XDG_SESSION_TYPE=wayland
      export NIRI_TTY_GUARD=1

      if [[ -n "${NIRI_OSC_CMD}" ]]; then
        exec "${NIRI_OSC_CMD}" set tty
      fi

      echo "ERROR: niri-osc not found, falling back to direct niri"
      sleep 2
      exec niri --session 2>&1 | tee /tmp/niri-tty2.log
      ;;

    3)
      echo "TTY3: launching Hyprland via hypr-set tty"
      export XDG_SESSION_TYPE=wayland

      if [[ -n "${HYPR_SET_CMD}" ]]; then
        exec "${HYPR_SET_CMD}" tty
      fi

      echo "ERROR: hypr-set not found, falling back to direct Hyprland"
      sleep 2
      exec Hyprland 2>&1 | tee /tmp/hyprland-tty3.log
      ;;

    4)
      echo "TTY4: launching GNOME via gnome_tty"
      export GNOME_TTY_GUARD=1
      export GNOME_TTY_GUARD_FILE="${XDG_RUNTIME_DIR}/gnome-tty4.guard"

      if [[ -e "${GNOME_TTY_GUARD_FILE}" ]]; then
        echo "GNOME guard active, skip duplicate launch."
        return
      fi

      if [[ -n "${GNOME_TTY_CMD}" ]]; then
        exec "${GNOME_TTY_CMD}"
      fi

      echo "ERROR: gnome_tty not found, falling back to gnome-session"
      sleep 2
      export XDG_SESSION_TYPE=wayland
      exec gnome-session --session=gnome --no-reexec 2>&1 | tee /tmp/gnome-session-tty4.log
      ;;

    5)
      echo "TTY5: launching Ubuntu VM profile in Sway"
      unset XDG_CURRENT_DESKTOP XDG_SESSION_DESKTOP DESKTOP_SESSION
      export XDG_SESSION_TYPE=wayland
      export XDG_SESSION_DESKTOP=sway
      export XDG_CURRENT_DESKTOP=sway
      export DESKTOP_SESSION=sway

      if [[ -f "${HOME}/.config/sway/qemu_vmubuntu" ]]; then
        exec sway -c "${HOME}/.config/sway/qemu_vmubuntu" 2>&1 | tee /tmp/sway-tty5.log
      fi

      echo "ERROR: missing sway config: ${HOME}/.config/sway/qemu_vmubuntu"
      sleep 3
      ;;

    6)
      echo "TTY6: manual mode (no autostart)"
      echo "Available routes:"
      echo "  TTY2 -> Niri      (${NIRI_OSC_CMD:-niri-osc} set tty)"
      echo "  TTY3 -> Hyprland  (${HYPR_SET_CMD:-hypr-set} tty)"
      echo "  TTY4 -> GNOME     (${GNOME_TTY_CMD:-gnome_tty})"
      echo "  TTY5 -> Sway VM   (sway -c ~/.config/sway/qemu_vmubuntu)"
      echo
      echo "Manual start commands:"
      echo "  exec ${NIRI_OSC_CMD:-niri-osc} set tty"
      echo "  exec ${HYPR_SET_CMD:-hypr-set} tty"
      echo "  exec ${GNOME_TTY_CMD:-gnome_tty}"
      ;;

    *)
      echo "TTY${XDG_VTNR}: no autostart route configured"
      echo "Use TTY6 for manual launch hints."
      ;;
  esac
fi
