#!/usr/bin/env bash
set -euo pipefail

status="$(mullvad status 2>/dev/null || true)"
vpn=0
blocky=0
blocked=0
dns=""
auto_dns=0
primary_con=""

printf '%s' "$status" | grep -q 'Connected' && vpn=1 || true
systemctl is-active --quiet blocky.service >/dev/null 2>&1 && blocky=1 || true
printf '%s' "$status" | grep -Eqi 'Blocked:|device has been revoked' && blocked=1 || true

if command -v nmcli >/dev/null 2>&1; then
  primary_con="$(nmcli -t -f NAME,DEVICE connection show --active 2>/dev/null | awk -F: '$2 != "lo" && $2 !~ /^wg/ {print $1; exit}' || true)"
  if [[ -n "$primary_con" ]]; then
    dns="$(nmcli -g IP4.DNS connection show "$primary_con" 2>/dev/null | grep -Eo '([0-9]{1,3}\.){3}[0-9]{1,3}' | paste -sd' ' - || true)"
    ignore_auto="$(nmcli -g ipv4.ignore-auto-dns connection show "$primary_con" 2>/dev/null | tail -n1 | tr -d '[:space:]' || true)"
    if [[ -z "$ignore_auto" || "$ignore_auto" == "no" || "$ignore_auto" == "false" ]]; then
      auto_dns=1
    fi
  fi
fi

if [[ -z "$dns" ]] && [[ -r /etc/resolv.conf ]]; then
  dns="$(grep -Eo '([0-9]{1,3}\.){3}[0-9]{1,3}' /etc/resolv.conf 2>/dev/null | paste -sd' ' - || true)"
fi

dns="$(printf '%s' "$dns" | tr ' ' '\n' | awk 'NF && !seen[$0]++' | paste -sd' ' - || true)"

printf '{"vpn_connected":%s,"blocky_active":%s,"blocked":%s,"auto_dns":%s,"dns":"%s"}\n' "$vpn" "$blocky" "$blocked" "$auto_dns" "$dns"
