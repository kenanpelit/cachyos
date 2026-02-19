#!/usr/bin/env bash
# ==============================================================================
# osc-logs-status
# ------------------------------------------------------------------------------
# Unified health check for system log management.
#
# What it checks:
#   1) Managed files from logs module
#   2) Effective journald limits
#   3) Journal disk usage
#   4) logrotate timer health
#   5) logrotate debug errors (duplicate/parse)
#   6) /var/log footprint
#   7) logrotate state entries for key logs
#
# Usage:
#   osc-logs-status
#   osc-logs-status --help
#   osc-logs-status --plain
# ==============================================================================

set -Eeuo pipefail

SCRIPT_NAME="$(basename "$0")"
CMD_NAME="${SCRIPT_NAME%.sh}"
VERSION="1.0.0"

PLAIN=false

JOURNALD_DROPIN="/etc/systemd/journald.conf.d/10-logs.conf"
LOGROTATE_DROPIN="/etc/logrotate.d/logs"
ATOP_DEFAULTS="/etc/default/atop"
LOGROTATE_STATE="/var/lib/logrotate.status"

FAIL_COUNT=0
WARN_COUNT=0

if [[ -t 1 && "${NO_COLOR:-}" != "1" ]]; then
  BOLD=$'\e[1m'
  DIM=$'\e[2m'
  RED=$'\e[31m'
  GRN=$'\e[32m'
  YLW=$'\e[33m'
  BLU=$'\e[34m'
  CYN=$'\e[36m'
  RST=$'\e[0m'
else
  BOLD="" DIM="" RED="" GRN="" YLW="" BLU="" CYN="" RST=""
fi

die() {
  echo "ERROR: $*" >&2
  exit 1
}

have() {
  command -v "$1" >/dev/null 2>&1
}

as_root() {
  if [[ "$(id -u)" -eq 0 ]]; then
    "$@"
  else
    if ! have sudo; then
      die "sudo is required to read system log state"
    fi
    sudo "$@"
  fi
}

print_banner() {
  $PLAIN && return 0
  cat <<EOF
${BOLD}${CYN}OSC Logs Status${RST} ${DIM}v${VERSION}${RST}
${DIM}System log management health check${RST}
EOF
  echo
}

section() {
  if $PLAIN; then
    echo "[$1/7] $2"
  else
    echo "${BOLD}${BLU}[$1/7]${RST} ${BOLD}$2${RST}"
  fi
}

ok() {
  if $PLAIN; then
    echo "OK: $*"
  else
    echo "${GRN}OK${RST}: $*"
  fi
}

warn() {
  WARN_COUNT=$((WARN_COUNT + 1))
  if $PLAIN; then
    echo "WARN: $*"
  else
    echo "${YLW}WARN${RST}: $*"
  fi
}

fail() {
  FAIL_COUNT=$((FAIL_COUNT + 1))
  if $PLAIN; then
    echo "FAIL: $*"
  else
    echo "${RED}FAIL${RST}: $*"
  fi
}

usage() {
  cat <<EOF
${CMD_NAME} - system log health checker

Usage:
  ${CMD_NAME} [OPTIONS]

Options:
  --plain         Plain output (no colors/decorative lines)
  -h, --help      Show this help

Exit codes:
  0  No hard failure detected
  1  One or more hard failures detected
EOF
}

check_requirements() {
  local missing=0
  local req=(systemd-analyze journalctl systemctl logrotate ls du grep sed awk)
  local cmd
  for cmd in "${req[@]}"; do
    if ! have "$cmd"; then
      echo "Missing required command: $cmd" >&2
      missing=1
    fi
  done
  [[ $missing -eq 0 ]] || exit 1
}

run_checks() {
  local catcfg keys lr

  keys='^(Storage|SystemMaxUse|SystemKeepFree|RuntimeMaxUse|MaxRetentionSec)='

  section 1 "Managed files"
  if as_root test -f "$JOURNALD_DROPIN" && as_root test -f "$LOGROTATE_DROPIN"; then
    as_root ls -l "$JOURNALD_DROPIN" "$LOGROTATE_DROPIN"
    ok "Managed files exist"
  else
    fail "Managed files missing (${JOURNALD_DROPIN} or ${LOGROTATE_DROPIN})"
  fi

  if as_root test -f "$ATOP_DEFAULTS"; then
    as_root grep '^LOGGENERATIONS=' "$ATOP_DEFAULTS" || warn "LOGGENERATIONS not set in ${ATOP_DEFAULTS}"
  else
    warn "${ATOP_DEFAULTS} not found (atop may be uninstalled)"
  fi
  echo

  section 2 "Effective journald values"
  catcfg="$(as_root systemd-analyze cat-config systemd/journald.conf 2>/dev/null || true)"
  if [[ -n "$catcfg" ]]; then
    echo "$catcfg" | grep -E "$keys" || warn "Could not parse journald keys"

    # Multiple SystemMaxUse definitions are valid but worth surfacing.
    local smu_count
    smu_count="$(echo "$catcfg" | grep -c '^SystemMaxUse=' || true)"
    if [[ "${smu_count}" -gt 1 ]]; then
      warn "Multiple SystemMaxUse entries detected (${smu_count}); last one wins"
    else
      ok "Single SystemMaxUse entry detected"
    fi
  else
    fail "systemd-analyze cat-config returned no output"
  fi
  echo

  section 3 "Journal disk usage"
  if ! as_root journalctl --disk-usage; then
    fail "journalctl --disk-usage failed"
  fi
  echo

  section 4 "logrotate timer"
  if as_root systemctl is-enabled logrotate.timer >/dev/null 2>&1; then
    ok "logrotate.timer is enabled"
  else
    fail "logrotate.timer is not enabled"
  fi
  as_root systemctl --no-pager --full status logrotate.timer | sed -n '1,12p' || warn "Could not print timer status"
  echo

  section 5 "logrotate debug (no change)"
  lr="$(as_root logrotate -d /etc/logrotate.conf 2>&1 || true)"
  if echo "$lr" | grep -Eqi 'duplicate log entry|found error in file|error:'; then
    fail "logrotate reported parse/duplicate errors"
    echo "$lr" | grep -Ei 'duplicate log entry|found error in file|error:' || true
  else
    ok "No duplicate/parse error in logrotate debug output"
  fi
  echo "$lr" | grep -Ei '/var/log/(pacman.log|mullvad-vpn)' || true
  echo

  section 6 "/var/log footprint"
  as_root du -msh /var/log /var/log/atop /var/log/journal 2>/dev/null || warn "Could not read some size paths"
  as_root ls -lh /var/log/{boot.log,pacman.log,snapper.log} 2>/dev/null || warn "One or more tracked log files missing"
  echo

  section 7 "logrotate state entries"
  if as_root test -f "$LOGROTATE_STATE"; then
    as_root grep -nE '/var/log/(pacman.log|mullvad-vpn)' "$LOGROTATE_STATE" || warn "No state entry for pacman/mullvad logs yet"
  else
    warn "${LOGROTATE_STATE} not found"
  fi
}

print_summary() {
  echo
  if [[ "$FAIL_COUNT" -gt 0 ]]; then
    echo "${BOLD}${RED}Summary:${RST} ${FAIL_COUNT} failure(s), ${WARN_COUNT} warning(s)"
    return 1
  fi

  if [[ "$WARN_COUNT" -gt 0 ]]; then
    echo "${BOLD}${YLW}Summary:${RST} 0 failures, ${WARN_COUNT} warning(s)"
  else
    echo "${BOLD}${GRN}Summary:${RST} all checks passed"
  fi
  return 0
}

main() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --plain)
        PLAIN=true
        shift
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        die "Unknown option: $1"
        ;;
    esac
  done

  check_requirements
  print_banner
  run_checks
  print_summary
}

main "$@"
