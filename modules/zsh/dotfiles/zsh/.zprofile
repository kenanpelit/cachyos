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

detect_tty_vtnr() {
  local current_tty=""

  if [[ "${XDG_VTNR:-}" =~ ^[0-9]+$ ]]; then
    printf '%s\n' "${XDG_VTNR}"
    return 0
  fi

  current_tty="$(tty 2>/dev/null || true)"
  case "${current_tty}" in
    /dev/tty[0-9]*)
      printf '%s\n' "${current_tty#/dev/tty}"
      return 0
      ;;
  esac

  return 1
}

log_tty_autostart() {
  local state_dir log_file
  state_dir="${XDG_STATE_HOME:-$HOME/.local/state}/zsh"
  log_file="${state_dir}/tty-autostart.log"

  mkdir -p "${state_dir}" 2>/dev/null || return 0
  printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >>"${log_file}" 2>/dev/null || true
}

is_login_shell=false
[[ -o login ]] && is_login_shell=true

tty_vtnr="$(detect_tty_vtnr 2>/dev/null || true)"

if $is_login_shell \
  && [[ -z "${WAYLAND_DISPLAY:-}" ]] \
  && [[ -z "${DISPLAY:-}" ]] \
  && [[ "${tty_vtnr:-}" =~ ^[1-6]$ ]] \
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
  if [[ "${tty_vtnr}" == "1" && -n "${XDG_SESSION_TYPE:-}" ]]; then
    log_tty_autostart "skip tty1 due to existing session type=${XDG_SESSION_TYPE}"
    return
  fi

  uid="$(id -u)"
  export XDG_RUNTIME_DIR="/run/user/${uid}"
  export SYSTEMD_OFFLINE=0
  export XDG_VTNR="${tty_vtnr}"

  TTY_LAUNCHER_CMD="$(resolve_cmd "${HOME}/.local/bin/osc-tty-launcher" "osc-tty-launcher" 2>/dev/null || true)"

  if [[ -z "${TTY_LAUNCHER_CMD}" ]]; then
    log_tty_autostart "launcher missing tty=${tty_vtnr}"
    echo "TTY launcher not found: osc-tty-launcher" >&2
    return
  fi

  log_tty_autostart "route tty=${tty_vtnr} launcher=${TTY_LAUNCHER_CMD}"

  case "${tty_vtnr}" in
    1)
      "${TTY_LAUNCHER_CMD}" auto-tty "${tty_vtnr}"
      ;;

    2)
      exec "${TTY_LAUNCHER_CMD}" auto-tty "${tty_vtnr}"
      ;;

    3)
      exec "${TTY_LAUNCHER_CMD}" auto-tty "${tty_vtnr}"
      ;;

    4)
      exec "${TTY_LAUNCHER_CMD}" auto-tty "${tty_vtnr}"
      ;;

    5)
      exec "${TTY_LAUNCHER_CMD}" auto-tty "${tty_vtnr}"
      ;;

    6)
      "${TTY_LAUNCHER_CMD}" auto-tty "${tty_vtnr}"
      ;;

    *)
      log_tty_autostart "no route tty=${tty_vtnr}"
      echo "TTY${tty_vtnr}: no autostart route configured"
      echo "Use TTY6 for manual launch hints."
      ;;
  esac
fi
