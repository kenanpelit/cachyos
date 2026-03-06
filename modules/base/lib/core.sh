#!/usr/bin/env bash
# ==============================================================================
# DCLI Core Library (modules/base/lib/core.sh)
# Common functions for declarative module scripts.
# ==============================================================================

# --- User & Environment Detection ---
# Detects the real user running the script, even if invoked via sudo
get_real_user() {
  if [[ -n "${SUDO_USER:-}" ]]; then
    echo "$SUDO_USER"
  else
    whoami
  fi
}

# Gets the home directory of the real user
get_user_home() {
  local real_user="$1"
  local uhome
  uhome="$(getent passwd "$real_user" | cut -d: -f6 2>/dev/null || true)"
  if [[ -z "$uhome" ]]; then
    uhome="$(eval echo "~$real_user")"
  fi
  echo "$uhome"
}

# Gets the standard runtime directory for the user
get_runtime_dir() {
  local real_user="$1"
  local uid
  uid="$(id -u "$real_user")"
  echo "/run/user/$uid"
}

# --- Execution Wrappers ---
# Runs a command as the real user, ensuring correct environment variables (like DBUS and XDG)
run_as_user() {
  local real_user
  real_user="$(get_real_user)"
  
  if [[ "$real_user" != "$(whoami)" ]]; then
    local uid
    uid="$(id -u "$real_user")"
    sudo -E -u "$real_user" \
      XDG_RUNTIME_DIR="/run/user/$uid" \
      DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$uid/bus" \
      "$@"
  else
    "$@"
  fi
}

# --- File Operations ---
# Idempotent install: prevents "are the same file" errors and ensures correct ownership
safe_install() {
  local src="$1"
  local dst="$2"
  local mode="${3:-644}"
  local real_user
  real_user="$(get_real_user)"

  [[ -f "$src" ]] || return 0
  if [[ -e "$dst" ]] && [[ "$src" -ef "$dst" ]]; then
    return 0
  fi

  run_as_user install -Dm"$mode" -- "$src" "$dst"
}

# --- Logging ---
# Standardized logging output
log_info() { echo -e "\033[0;34m[INFO]\033[0m $*"; }
log_success() { echo -e "\033[0;32m[SUCCESS]\033[0m $*"; }
log_warn() { echo -e "\033[1;33m[WARN]\033[0m $*" >&2; }
log_error() { echo -e "\033[0;31m[ERROR]\033[0m $*" >&2; }
die() { log_error "$*"; exit 1; }

# Initialize common variables for sourcing scripts
REAL_USER="$(get_real_user)"
USER_HOME="$(get_user_home "$REAL_USER")"
USER_RUNTIME="$(get_runtime_dir "$REAL_USER")"
CACHY_RUNTIME="${USER_RUNTIME}/cachy"

# Ensure our isolated state directory exists
if [[ "$(id -u)" -eq 0 ]]; then
  install -d -m 0700 -o "$REAL_USER" "$CACHY_RUNTIME" 2>/dev/null || true
else
  mkdir -p "$CACHY_RUNTIME"
  chmod 0700 "$CACHY_RUNTIME"
fi
