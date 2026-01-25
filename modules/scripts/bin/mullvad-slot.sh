#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# mullvad-slot.sh
# ------------------------------------------------------------------------------
# Purpose:
#   Manage a single "ephemeral" Mullvad device slot without systemd.
#
# Core workflow (recommended on the changing machine):
#   recycle:
#     - revoke the previously recorded device name (best-effort)
#     - login if needed (env var or pass)
#     - connect
#     - record the current device name for next time
#
# Secrets (priority order):
#   1) MULLVAD_ACCOUNT_NUMBER (exported env var)
#   2) pass entry (default: mullvad/account) via MULLVAD_PASS_ENTRY
#
# Notifications:
#   - Uses notify-send if available (libnotify).
#   - Never prints or notifies the account number.
#
# State:
#   - Default state file:
#       ${XDG_STATE_HOME:-$HOME/.local/state}/mullvad-slot/last_device
#   - Override with: MULLVAD_SLOT_STATE_FILE
#
# Safety:
#   - Never revokes the currently active device name.
# ==============================================================================

# ------------------------------ Config ----------------------------------------
STATE_DIR_DEFAULT="${XDG_STATE_HOME:-$HOME/.local/state}/mullvad-slot"
STATE_FILE="${MULLVAD_SLOT_STATE_FILE:-$STATE_DIR_DEFAULT/last_device}"

PASS_ENTRY="${MULLVAD_PASS_ENTRY:-mullvad/account}"

DRY_RUN="false"

# Notification metadata
NOTIFY_APP_NAME="${MULLVAD_NOTIFY_APP_NAME:-mullvad-slot}"
NOTIFY_TIMEOUT_MS="${MULLVAD_NOTIFY_TIMEOUT_MS:-2500}"

# ------------------------------ Styling ---------------------------------------
if [[ -t 1 ]]; then
  C_RESET=$'\e[0m'
  C_DIM=$'\e[2m'
  C_RED=$'\e[31m'
  C_GRN=$'\e[32m'
  C_YLW=$'\e[33m'
  C_BLU=$'\e[34m'
  C_MAG=$'\e[35m'
  C_CYN=$'\e[36m'
else
  C_RESET=""
  C_DIM=""
  C_RED=""
  C_GRN=""
  C_YLW=""
  C_BLU=""
  C_MAG=""
  C_CYN=""
fi

log() { printf '%s\n' "${C_CYN}==>${C_RESET} $*"; }
ok() { printf '%s\n' "${C_GRN}OK:${C_RESET} $*"; }
warn() { printf '%s\n' "${C_YLW}WARN:${C_RESET} $*" >&2; }
die() {
  printf '%s\n' "${C_RED}ERROR:${C_RESET} $*" >&2
  exit 1
}

# ------------------------------ Utilities -------------------------------------
need_cmd() { command -v "$1" >/dev/null 2>&1 || die "Missing command: $1"; }

do_cmd() {
  if [[ "$DRY_RUN" == "true" ]]; then
    printf '%s\n' "${C_DIM}[dry-run]${C_RESET} $*"
    return 0
  fi
  "$@"
}

notify() {
  # notify <urgency> <title> <body>
  # urgency: low|normal|critical
  local urgency="${1:-normal}"
  local title="${2:-mullvad-slot}"
  local body="${3:-}"

  if command -v notify-send >/dev/null 2>&1; then
    # Do not fail script if notifications fail
    notify-send \
      --app-name="$NOTIFY_APP_NAME" \
      --urgency="$urgency" \
      --expire-time="$NOTIFY_TIMEOUT_MS" \
      "$title" "$body" >/dev/null 2>&1 || true
  fi
}

ensure_state_dir() {
  local dir
  dir="$(dirname "$STATE_FILE")"
  mkdir -p "$dir"
  chmod 0700 "$dir" 2>/dev/null || true
}

read_last_device() {
  [[ -f "$STATE_FILE" ]] || return 0
  cat "$STATE_FILE" 2>/dev/null || true
}

write_last_device() {
  local dev="$1"
  ensure_state_dir
  if [[ "$DRY_RUN" == "true" ]]; then
    log "Would record device '${dev}' -> $STATE_FILE"
    return 0
  fi
  printf '%s' "$dev" >"$STATE_FILE"
  chmod 0600 "$STATE_FILE" 2>/dev/null || true
}

# ------------------------------ Mullvad helpers -------------------------------
is_logged_in() {
  mullvad account get >/dev/null 2>&1
}

current_device_name() {
  # Your CLI prints: "Device name:        Live Coral"
  mullvad account get 2>/dev/null | awk -F': *' '/^Device name:/ {print $2; exit}'
}

list_devices() {
  # Robust parsing: keep only non-empty lines that are not the header.
  mullvad account list-devices 2>/dev/null | awk '
    /^[[:space:]]*Devices on the account:[[:space:]]*$/ { next }
    /^[[:space:]]*$/ { next }
    { print }
  '
}

resolve_account_number() {
  # 1) Explicit env var wins
  if [[ -n "${MULLVAD_ACCOUNT_NUMBER:-}" ]]; then
    printf '%s' "$MULLVAD_ACCOUNT_NUMBER"
    return 0
  fi

  # 2) Try pass
  if command -v pass >/dev/null 2>&1; then
    if pass show "$PASS_ENTRY" >/dev/null 2>&1; then
      pass show "$PASS_ENTRY" | head -n1 | tr -d '[:space:]'
      return 0
    fi
  fi

  return 1
}

login_if_needed() {
  if is_logged_in; then
    return 0
  fi

  local acc
  if ! acc="$(resolve_account_number)"; then
    die "Not logged in. Export MULLVAD_ACCOUNT_NUMBER or store it in pass ($PASS_ENTRY)."
  fi

  log "Logging in to Mullvad account (secret not shown)"
  do_cmd mullvad account login "$acc" >/dev/null
  ok "Logged in"
}

revoke_device() {
  local dev="$1"
  [[ -n "$dev" ]] || return 0

  local cur
  cur="$(current_device_name || true)"

  # Safety: never revoke current device
  if [[ -n "$cur" && "$dev" == "$cur" ]]; then
    warn "Refusing to revoke current device: '$dev'"
    return 0
  fi

  if do_cmd mullvad account revoke-device "$dev" >/dev/null 2>&1; then
    ok "Revoked device: $dev"
    notify normal "Mullvad slot" "Revoked: $dev"
  else
    warn "Failed to revoke device: '$dev' (maybe already gone?)"
  fi
}

connect() {
  # Optional: force WireGuard. Harmless if already set.
  do_cmd mullvad relay set tunnel-protocol wireguard >/dev/null 2>&1 || true

  log "Connecting Mullvad…"
  if do_cmd mullvad connect >/dev/null 2>&1; then
    ok "Connected"
    notify normal "Mullvad" "Connected"
  else
    notify critical "Mullvad" "Connect failed"
    die "mullvad connect failed"
  fi
}

disconnect() {
  log "Disconnecting Mullvad…"
  do_cmd mullvad disconnect >/dev/null 2>&1 || true
  ok "Disconnected"
  notify normal "Mullvad" "Disconnected"
}

record_current_device() {
  local dev
  dev="$(current_device_name || true)"
  [[ -n "$dev" ]] || die "Could not determine current device name (mullvad account get)."
  write_last_device "$dev"
  ok "Recorded device: $dev"
  notify normal "Mullvad slot" "Recorded device: $dev"
}

# ------------------------------ Commands --------------------------------------
usage() {
  cat <<EOF
Usage:
  $(basename "$0") [--dry-run] <command> [args...]

Commands:
  recycle                Revoke last recorded device -> connect -> record new device
  remember               Record current device name into state file
  whoami                 Print current device name
  list                   List all devices on the account
  revoke "<name>"        Revoke a specific device by exact name
  status                 Show mullvad status + current device + state file
  disconnect             Disconnect VPN (no revoke)
  cleanup "<keep1>" ...  Revoke ALL devices except the ones you list (DANGEROUS)

Env:
  MULLVAD_ACCOUNT_NUMBER=1234123412341234      # optional if pass is configured
  MULLVAD_PASS_ENTRY=mullvad/account           # default
  MULLVAD_SLOT_STATE_FILE=/path/to/last_device # override default state file
  MULLVAD_NOTIFY_TIMEOUT_MS=2500               # default 2500

State file:
  $STATE_FILE

Examples:
  # Recommended: run on the changing machine
  $(basename "$0") recycle

  # Dry-run
  $(basename "$0") --dry-run recycle

  # Keep only stable devices (plus current device auto-added for safety)
  $(basename "$0") cleanup "Golden Cicada" "Cute Puffer"
EOF
}

cmd_recycle() {
  need_cmd mullvad
  ensure_state_dir
  login_if_needed

  local last
  last="$(read_last_device || true)"

  if [[ -n "$last" ]]; then
    log "Last recorded device: $last"
    revoke_device "$last"
  else
    warn "No last recorded device found (first run?)"
  fi

  connect
  record_current_device

  local cur
  cur="$(current_device_name || true)"
  [[ -n "$cur" ]] && log "Current device: $cur"
}

cmd_remember() {
  need_cmd mullvad
  login_if_needed
  record_current_device
}

cmd_whoami() {
  need_cmd mullvad
  login_if_needed
  current_device_name
}

cmd_list() {
  need_cmd mullvad
  login_if_needed
  list_devices
}

cmd_status() {
  need_cmd mullvad
  login_if_needed

  echo "== mullvad status =="
  mullvad status || true
  echo
  echo "== current device =="
  echo "$(current_device_name || true)"
  echo
  echo "== state file =="
  echo "STATE_FILE=$STATE_FILE"
  if [[ -f "$STATE_FILE" ]]; then
    echo -n "last_device="
    cat "$STATE_FILE" || true
    echo
  else
    echo "last_device=<none>"
  fi
}

cmd_revoke() {
  need_cmd mullvad
  login_if_needed
  [[ $# -ge 1 ]] || die "revoke requires a device name"
  revoke_device "$*"
}

cmd_disconnect() {
  need_cmd mullvad
  disconnect
}

cmd_cleanup() {
  need_cmd mullvad
  login_if_needed
  [[ $# -ge 1 ]] || die "cleanup requires at least one device name to keep"

  declare -A keep=()
  local k
  for k in "$@"; do keep["$k"]=1; done

  local cur
  cur="$(current_device_name || true)"
  if [[ -n "$cur" && -z "${keep[$cur]+x}" ]]; then
    warn "Current device ('$cur') is NOT in keep-list. Adding it for safety."
    keep["$cur"]=1
  fi

  log "Keeping devices:"
  for k in "${!keep[@]}"; do echo "  - $k"; done
  echo

  local dev
  while IFS= read -r dev; do
    [[ -n "$dev" ]] || continue
    if [[ -n "${keep[$dev]+x}" ]]; then
      echo "KEEP: $dev"
    else
      echo "DROP: $dev"
      revoke_device "$dev"
    fi
  done < <(list_devices)

  notify normal "Mullvad cleanup" "Cleanup complete"
  ok "Cleanup complete"
}

# ------------------------------ Arg parse -------------------------------------
if [[ "${1:-}" == "--dry-run" ]]; then
  DRY_RUN="true"
  shift
fi

cmd="${1:-}"
shift || true

case "$cmd" in
recycle) cmd_recycle "$@" ;;
remember) cmd_remember "$@" ;;
whoami) cmd_whoami "$@" ;;
list) cmd_list "$@" ;;
revoke) cmd_revoke "$@" ;;
status) cmd_status "$@" ;;
disconnect) cmd_disconnect "$@" ;;
cleanup) cmd_cleanup "$@" ;;
-h | --help | help | "") usage ;;
*) die "Unknown command: $cmd (use --help)" ;;
esac
