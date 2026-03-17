# shellcheck shell=bash
# =============================================================================
# Multi-TTY desktop autostart router (login shell only)
# =============================================================================
# TTY1: display manager / manual launch info
# TTY2: Hyprland (UWSM)
# TTY3: Niri (UWSM)
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
[[ -o login ]] && is_login_shell=true

if $is_login_shell \
  && [[ -z "${WAYLAND_DISPLAY:-}" ]] \
  && [[ -z "${DISPLAY:-}" ]]; then
  TTY_AUTOSTART_CMD="$(resolve_cmd "${HOME}/.local/bin/osc-tty-autostart" "osc-tty-autostart" 2>/dev/null || true)"
  [[ -n "${TTY_AUTOSTART_CMD}" ]] && "${TTY_AUTOSTART_CMD}" || true
fi
