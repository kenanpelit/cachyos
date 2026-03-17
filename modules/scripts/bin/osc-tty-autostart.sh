#!/usr/bin/env bash
# ==============================================================================
# Script: osc-tty-autostart.sh
# Description: Shared TTY autostart entry used by zsh login/interactive shells.
# Usage: osc-tty-autostart
# ==============================================================================
set -euo pipefail

SCRIPT_NAME="$(basename "$0")"

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

main() {
  local tty_vtnr=""
  local launcher_cmd=""
  local uid

  [[ -z "${OSC_TTY_AUTOSTART_ATTEMPTED:-}" ]] || exit 0
  [[ -z "${OSC_TTY_LAUNCHER_GUARD:-}" ]] || exit 0
  [[ -z "${NIRI_TTY_GUARD:-}" ]] || exit 0
  [[ -z "${GNOME_TTY_GUARD:-}" ]] || exit 0
  [[ -z "${WAYLAND_DISPLAY:-}" ]] || exit 0
  [[ -z "${DISPLAY:-}" ]] || exit 0

  tty_vtnr="$(detect_tty_vtnr 2>/dev/null || true)"
  [[ "${tty_vtnr:-}" =~ ^[1-6]$ ]] || exit 0

  if pgrep -u "$(id -u)" -x gnome-shell >/dev/null 2>&1 \
    || [[ -n "${GNOME_DESKTOP_SESSION_ID:-}" ]] \
    || [[ -n "${GNOME_SHELL_SESSION_MODE:-}" ]]; then
    log_tty_autostart "skip due to active gnome-shell tty=${tty_vtnr}"
    exit 0
  fi

  if [[ "${tty_vtnr}" == "1" && -n "${XDG_SESSION_TYPE:-}" ]]; then
    log_tty_autostart "skip tty1 due to existing session type=${XDG_SESSION_TYPE}"
    exit 0
  fi

  export OSC_TTY_AUTOSTART_ATTEMPTED=1

  uid="$(id -u)"
  export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/${uid}}"
  export SYSTEMD_OFFLINE=0
  export XDG_VTNR="${tty_vtnr}"

  launcher_cmd="$(resolve_cmd "${HOME}/.local/bin/osc-tty-launcher" "osc-tty-launcher" 2>/dev/null || true)"
  if [[ -z "${launcher_cmd}" ]]; then
    log_tty_autostart "launcher missing tty=${tty_vtnr}"
    exit 0
  fi

  log_tty_autostart "route tty=${tty_vtnr} launcher=${launcher_cmd}"

  case "${tty_vtnr}" in
    1|6)
      "${launcher_cmd}" auto-tty "${tty_vtnr}"
      ;;
    2|3|4|5)
      exec "${launcher_cmd}" auto-tty "${tty_vtnr}"
      ;;
  esac
}

main "$@"
