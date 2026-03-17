# shellcheck shell=bash
# =============================================================================
# Multi-TTY desktop autostart router (login shell only)
# =============================================================================
# TTY1: display manager / manual launch info
# TTY2: Niri (UWSM)
# TTY3: Hyprland (UWSM)
# TTY4: GNOME (gnome_tty)
# TTY5: VM route (svmubuntu via Sway profile)
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
  && [[ -z "${OSC_TTY_LAUNCHER_GUARD:-}" ]] \
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
  export SYSTEMD_OFFLINE=0

  TTY_LAUNCHER_CMD="$(resolve_cmd "${HOME}/.local/bin/osc-tty-launcher" "osc-tty-launcher" 2>/dev/null || true)"

  if [[ -z "${TTY_LAUNCHER_CMD}" ]]; then
    echo "TTY launcher not found: osc-tty-launcher" >&2
    return
  fi

  case "${XDG_VTNR}" in
    1)
      "${TTY_LAUNCHER_CMD}" auto-tty "${XDG_VTNR}"
      ;;

    2)
      exec "${TTY_LAUNCHER_CMD}" auto-tty "${XDG_VTNR}"
      ;;

    3)
      exec "${TTY_LAUNCHER_CMD}" auto-tty "${XDG_VTNR}"
      ;;

    4)
      exec "${TTY_LAUNCHER_CMD}" auto-tty "${XDG_VTNR}"
      ;;

    5)
      exec "${TTY_LAUNCHER_CMD}" auto-tty "${XDG_VTNR}"
      ;;

    6)
      "${TTY_LAUNCHER_CMD}" auto-tty "${XDG_VTNR}"
      ;;

    *)
      echo "TTY${XDG_VTNR}: no autostart route configured"
      echo "Use TTY6 for manual launch hints."
      ;;
  esac
fi
