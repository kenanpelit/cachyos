#!/usr/bin/env bash
# ==============================================================================
# Script: mango-session-doctor
# Description: Print a compact MangoWM session diagnostics report.
# Usage: mango-session-doctor
# ==============================================================================

set -euo pipefail

print_section() {
  printf '\n== %s ==\n' "$1"
}

print_env_var() {
  local name="$1"
  printf '%-20s %s\n' "${name}" "${!name:-<unset>}"
}

print_service_state() {
  local service="$1"
  local state="unknown"
  if command -v systemctl >/dev/null 2>&1; then
    state="$(systemctl --user is-active "${service}" 2>/dev/null || true)"
    [[ -n "${state}" ]] || state="inactive"
  fi
  printf '%-32s %s\n' "${service}" "${state}"
}

main() {
  print_section "Session"
  print_env_var XDG_CURRENT_DESKTOP
  print_env_var XDG_SESSION_DESKTOP
  print_env_var DESKTOP_SESSION
  print_env_var XDG_SESSION_TYPE
  print_env_var WAYLAND_DISPLAY
  print_env_var DISPLAY

  print_section "Mango Services"
  print_service_state mangowm-session.target
  print_service_state mango-session-env.service
  print_service_state mango-bootstrap.service
  print_service_state mango-post-bootstrap.service
  print_service_state mango-shell-ensure.service
  print_service_state mango-status-notifier-ready.service

  print_section "Manager Environment"
  if command -v systemctl >/dev/null 2>&1; then
    systemctl --user show-environment 2>/dev/null | \
      grep -E '^(WAYLAND_DISPLAY|DISPLAY|XDG_CURRENT_DESKTOP|XDG_SESSION_DESKTOP|XDG_SESSION_TYPE|DESKTOP_SESSION)=' || true
  else
    printf 'systemctl not available\n'
  fi

  if [[ -t 1 ]]; then
    printf '\nPress any key to close...'
    IFS= read -r -n 1 _ || true
    printf '\n'
  fi
}

main "$@"
