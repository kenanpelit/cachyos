#!/usr/bin/env bash
set -euo pipefail

osc_input="${1:-osc-mullvad}"
action="${2:-}"
dns_value="${3:-}"

resolve_osc() {
  local home_bin=""

  if [[ -x "$osc_input" ]]; then
    OSC_BIN="$osc_input"
    return 0
  fi

  if [[ "$osc_input" != */* && -n "${HOME:-}" ]]; then
    home_bin="${HOME}/.local/bin/${osc_input}"
    if [[ -x "$home_bin" ]]; then
      OSC_BIN="$home_bin"
      return 0
    fi
  fi

  OSC_BIN="$(command -v "$osc_input" 2>/dev/null || true)"
  if [[ -z "$OSC_BIN" ]]; then
    printf 'osc-mullvad not found: %s\n' "$osc_input" >&2
    exit 127
  fi
}

vpn_connected() {
  mullvad status 2>/dev/null | grep -q 'Connected'
}

blocky_active() {
  systemctl is-active --quiet blocky.service >/dev/null 2>&1
}

active_connection() {
  nmcli -t -f NAME,DEVICE connection show --active 2>/dev/null | awk -F: '$2 != "lo" && $2 !~ /^wg/ {print $1; exit}'
}

stop_blocky() {
  systemctl list-unit-files blocky.service >/dev/null 2>&1 || return 0
  blocky_active || return 0

  if sudo -n true >/dev/null 2>&1; then
    sudo systemctl stop blocky.service >/dev/null 2>&1 || return 1
    return 0
  fi

  if command -v pkexec >/dev/null 2>&1; then
    pkexec sh -c 'systemctl stop blocky.service >/dev/null 2>&1' || return 1
    return 0
  fi

  printf 'Cannot stop blocky.service (need sudo -n or pkexec)\n' >&2
  return 1
}

run_osc() {
  "$OSC_BIN" "$@"
}

set_dns_config() {
  local dns="$1"
  command -v nmcli >/dev/null 2>&1 || {
    printf 'nmcli not found\n' >&2
    return 127
  }

  local con
  con="$(active_connection)"
  [[ -n "$con" ]] || {
    printf 'No active NetworkManager connection\n' >&2
    return 21
  }

  if [[ -z "$dns" ]]; then
    nmcli con mod "$con" ipv4.dns '' ipv4.ignore-auto-dns no >/dev/null 2>&1 || return 22
  else
    nmcli con mod "$con" ipv4.dns "$dns" ipv4.ignore-auto-dns yes >/dev/null 2>&1 || return 22
  fi

  printf '%s\n' "$con"
}

set_dns() {
  local dns="$1"
  local con
  con="$(set_dns_config "$dns")"
  nmcli con up "$con" >/dev/null 2>&1 || return 23
}

clear_connection_dns() {
  set_dns ""
}

clear_connection_dns_config_only() {
  set_dns_config "" >/dev/null
}

direct_prep() {
  mullvad disconnect >/dev/null 2>&1 || true
  mullvad auto-connect set off >/dev/null 2>&1 || true
  mullvad lockdown-mode set off >/dev/null 2>&1 || true
  stop_blocky
}

resolve_osc

case "$action" in
  toggle)
    run_osc toggle --with-blocky
    ;;
  mullvad)
    if vpn_connected && ! blocky_active; then
      clear_connection_dns_config_only
      exit $?
    fi
    if vpn_connected && blocky_active; then
      run_osc ensure --grace 0
      clear_connection_dns_config_only
      exit $?
    fi
    run_osc toggle --with-blocky
    clear_connection_dns_config_only
    ;;
  blocky)
    if ! vpn_connected && blocky_active; then
      clear_connection_dns_config_only
      exit $?
    fi
    if vpn_connected; then
      run_osc toggle --with-blocky
    else
      run_osc ensure --grace 0
    fi
    clear_connection_dns_config_only
    ;;
  repair)
    run_osc ensure --grace 0
    ;;
  default)
    direct_prep
    clear_connection_dns
    ;;
  provider)
    direct_prep
    set_dns "$dns_value"
    ;;
  *)
    printf 'Unknown action: %s\n' "$action" >&2
    exit 2
    ;;
esac
