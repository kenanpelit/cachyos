#!/usr/bin/env bash
# ==============================================================================
# Script: osc-wifi-home.sh
# Description: NetworkManager connection setup for home WiFi (Ken_5 and Ken_2_4)
# Usage: osc-wifi-home.sh <Ken_5_Password> <Ken_2_4_Password>
# ==============================================================================

# ==============================================================================
# Script: osc-wifi-home.sh
# Description:
#   Create or recreate two NetworkManager Wi-Fi profiles for home use.
#
#   Profiles:
#     1) Ken_5
#        - Primary profile
#        - Forced to 5 GHz
#        - Static IPv4
#        - Higher autoconnect priority
#
#     2) Ken_2_4
#        - Secondary/fallback profile
#        - Forced to 2.4 GHz
#        - Static IPv4
#        - Lower autoconnect priority
#
#   DNS features:
#     - Supports DNS presets:
#         cloudflare | google | quad9 | adguard | opendns | blocky
#     - "blocky" preset uses localhost resolvers:
#         127.0.0.1 and ::1
#     - Auto DNS from router is disabled intentionally.
#
# Usage:
#   ./osc-wifi-home.sh <Ken_5_Password> <Ken_2_4_Password> [dns_preset]
#
# Examples:
#   ./osc-wifi-home.sh 'pass5' 'pass24'
#   ./osc-wifi-home.sh 'pass5' 'pass24' cloudflare
#   ./osc-wifi-home.sh 'pass5' 'pass24' blocky
#
# Notes:
#   - This script deletes old profiles with the same names and recreates them.
#   - Both Wi-Fi profiles use static IPv4 addresses.
#   - Adjust the IP settings below to match your LAN.
#   - Make sure the chosen IPs are reserved or not already in use.
# ==============================================================================

set -Eeuo pipefail

# ------------------------------------------------------------------------------
# User configuration
# ------------------------------------------------------------------------------

PRIMARY_CONN_NAME="Ken_5"
SECONDARY_CONN_NAME="Ken_2_4"

PRIMARY_SSID="Ken_5"
SECONDARY_SSID="Ken_2_4"

PRIMARY_IPV4_ADDRESS="192.168.0.100/24"
PRIMARY_IPV4_GATEWAY="192.168.0.1"
PRIMARY_ROUTE_METRIC="100"

SECONDARY_IPV4_ADDRESS="192.168.0.101/24"
SECONDARY_IPV4_GATEWAY="192.168.0.1"
SECONDARY_ROUTE_METRIC="200"

PRIMARY_PRIORITY="100"
SECONDARY_PRIORITY="10"

PRIMARY_AUTOCONNECT="yes"
SECONDARY_AUTOCONNECT="yes"

# 0 = default
# 1 = ignore
# 2 = disable
# 3 = enable
WIFI_POWERSAVE="2"

IPV6_METHOD="disabled"

# If set to "yes", the script activates the primary profile at the end.
AUTO_ACTIVATE_PRIMARY="yes"

# Set to "yes" if you want the secondary connection to never become the default route.
# Usually "no" is better for a real fallback profile.
SECONDARY_NEVER_DEFAULT="no"

# ------------------------------------------------------------------------------
# Logging helpers
# ------------------------------------------------------------------------------

log() {
  printf '[INFO] %s\n' "$*"
}

warn() {
  printf '[WARN] %s\n' "$*" >&2
}

die() {
  printf '[ERROR] %s\n' "$*" >&2
  exit 1
}

# ------------------------------------------------------------------------------
# Validation helpers
# ------------------------------------------------------------------------------

require_command() {
  command -v "$1" >/dev/null 2>&1 || die "Required command not found: $1"
}

validate_arguments() {
  if [[ $# -lt 2 || $# -gt 3 ]]; then
    cat >&2 <<EOF
Usage:
  $0 <Ken_5_Password> <Ken_2_4_Password> [dns_preset]

DNS presets:
  cloudflare
  google
  quad9
  adguard
  opendns
  blocky
EOF
    exit 1
  fi
}

validate_networkmanager() {
  nmcli general status >/dev/null 2>&1 || die "NetworkManager is not running or not accessible."
}

detect_wifi_interface() {
  local iface
  iface="$(
    nmcli -t -f DEVICE,TYPE,STATE device status |
      awk -F: '$2=="wifi" {print $1; exit}'
  )"

  [[ -n "${iface:-}" ]] || die "No Wi-Fi interface detected."
  printf '%s\n' "$iface"
}

# ------------------------------------------------------------------------------
# DNS preset handling
# ------------------------------------------------------------------------------

DNS_PRESET="${3:-blocky}"
DNS_IPV4=""
DNS_IPV6=""

set_dns_preset() {
  case "$DNS_PRESET" in
  cloudflare)
    DNS_IPV4="1.1.1.1 1.0.0.1"
    DNS_IPV6=""
    ;;
  google)
    DNS_IPV4="8.8.8.8 8.8.4.4"
    DNS_IPV6=""
    ;;
  quad9)
    DNS_IPV4="9.9.9.9 149.112.112.112"
    DNS_IPV6=""
    ;;
  adguard)
    DNS_IPV4="94.140.14.14 94.140.15.15"
    DNS_IPV6=""
    ;;
  opendns)
    DNS_IPV4="208.67.222.222 208.67.220.220"
    DNS_IPV6=""
    ;;
  blocky)
    DNS_IPV4="127.0.0.1"
    DNS_IPV6="::1"
    ;;
  *)
    die "Unsupported DNS preset: $DNS_PRESET"
    ;;
  esac
}

# ------------------------------------------------------------------------------
# Connection helpers
# ------------------------------------------------------------------------------

delete_connection_if_exists() {
  local conn_name="$1"

  if nmcli connection show "$conn_name" >/dev/null 2>&1; then
    log "Deleting existing connection profile: $conn_name"
    nmcli connection delete "$conn_name" >/dev/null
  fi
}

apply_common_dns_settings() {
  local conn_name="$1"

  nmcli connection modify "$conn_name" \
    ipv4.ignore-auto-dns yes \
    ipv4.dns "$DNS_IPV4" \
    ipv4.dns-search "" \
    >/dev/null

  if [[ -n "$DNS_IPV6" ]]; then
    nmcli connection modify "$conn_name" \
      ipv6.ignore-auto-dns yes \
      ipv6.dns "$DNS_IPV6" \
      >/dev/null
  fi
}

add_primary_connection() {
  local iface="$1"
  local password="$2"

  log "Creating primary 5 GHz profile: $PRIMARY_CONN_NAME"

  nmcli connection add \
    type wifi \
    ifname "$iface" \
    con-name "$PRIMARY_CONN_NAME" \
    ssid "$PRIMARY_SSID" \
    802-11-wireless.band a \
    wifi.powersave "$WIFI_POWERSAVE" \
    wifi-sec.key-mgmt wpa-psk \
    wifi-sec.psk "$password" \
    connection.autoconnect "$PRIMARY_AUTOCONNECT" \
    connection.autoconnect-priority "$PRIMARY_PRIORITY" \
    connection.interface-name "$iface" \
    802-11-wireless.cloned-mac-address permanent \
    ipv4.method manual \
    ipv4.addresses "$PRIMARY_IPV4_ADDRESS" \
    ipv4.gateway "$PRIMARY_IPV4_GATEWAY" \
    ipv4.route-metric "$PRIMARY_ROUTE_METRIC" \
    ipv4.may-fail no \
    ipv6.method "$IPV6_METHOD" \
    >/dev/null

  apply_common_dns_settings "$PRIMARY_CONN_NAME"
}

add_secondary_connection() {
  local iface="$1"
  local password="$2"

  log "Creating fallback 2.4 GHz profile: $SECONDARY_CONN_NAME"

  nmcli connection add \
    type wifi \
    ifname "$iface" \
    con-name "$SECONDARY_CONN_NAME" \
    ssid "$SECONDARY_SSID" \
    802-11-wireless.band bg \
    wifi.powersave "$WIFI_POWERSAVE" \
    wifi-sec.key-mgmt wpa-psk \
    wifi-sec.psk "$password" \
    connection.autoconnect "$SECONDARY_AUTOCONNECT" \
    connection.autoconnect-priority "$SECONDARY_PRIORITY" \
    connection.interface-name "$iface" \
    802-11-wireless.cloned-mac-address permanent \
    ipv4.method manual \
    ipv4.addresses "$SECONDARY_IPV4_ADDRESS" \
    ipv4.gateway "$SECONDARY_IPV4_GATEWAY" \
    ipv4.route-metric "$SECONDARY_ROUTE_METRIC" \
    ipv4.may-fail yes \
    ipv4.never-default "$SECONDARY_NEVER_DEFAULT" \
    ipv6.method "$IPV6_METHOD" \
    >/dev/null

  apply_common_dns_settings "$SECONDARY_CONN_NAME"
}

activate_primary_connection() {
  if [[ "$AUTO_ACTIVATE_PRIMARY" == "yes" ]]; then
    log "Activating primary profile: $PRIMARY_CONN_NAME"
    nmcli connection up "$PRIMARY_CONN_NAME" >/dev/null ||
      warn "Primary profile could not be activated immediately."
  fi
}

show_connection_details() {
  local conn_name="$1"

  printf '\n'
  printf -- '--- %s ---\n' "$conn_name"
  nmcli -f connection.id,connection.interface-name,connection.autoconnect,connection.autoconnect-priority,802-11-wireless.ssid,802-11-wireless.band,ipv4.method,ipv4.addresses,ipv4.gateway,ipv4.dns,ipv4.route-metric,ipv4.never-default,ipv6.method connection show "$conn_name"
}

show_summary() {
  printf '\n'
  printf '============================================================\n'
  printf 'Wi-Fi profiles recreated successfully.\n'
  printf '============================================================\n'
  printf 'DNS preset        : %s\n' "$DNS_PRESET"
  printf 'Wi-Fi interface   : %s\n' "$WIFI_IFACE"
  printf 'Primary profile   : %s\n' "$PRIMARY_CONN_NAME"
  printf 'Secondary profile : %s\n' "$SECONDARY_CONN_NAME"
  printf '============================================================\n'

  show_connection_details "$PRIMARY_CONN_NAME"
  show_connection_details "$SECONDARY_CONN_NAME"

  printf '\n'
  printf 'Active Wi-Fi scan:\n'
  nmcli -f IN-USE,SSID,CHAN,SIGNAL,SECURITY dev wifi list || true
}

# ------------------------------------------------------------------------------
# Main
# ------------------------------------------------------------------------------

main() {
  require_command nmcli
  validate_arguments "$@"
  validate_networkmanager
  set_dns_preset

  local primary_password="$1"
  local secondary_password="$2"

  WIFI_IFACE="$(detect_wifi_interface)"
  log "Detected Wi-Fi interface: $WIFI_IFACE"
  log "Selected DNS preset: $DNS_PRESET"

  delete_connection_if_exists "$PRIMARY_CONN_NAME"
  delete_connection_if_exists "$SECONDARY_CONN_NAME"

  add_primary_connection "$WIFI_IFACE" "$primary_password"
  add_secondary_connection "$WIFI_IFACE" "$secondary_password"

  activate_primary_connection
  show_summary
}

main "$@"
