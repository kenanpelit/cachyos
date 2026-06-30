#!/usr/bin/env bash
# ==============================================================================
# MDOTS Core Library (modules/base/lib/core.sh)
# Common functions for declarative module scripts.
# ==============================================================================

# --- User & Environment Detection ---
# Detects the real user running the script, even if invoked via sudo
get_real_user() {
  local current_uid current_user candidate

  current_uid="$(id -u)"
  current_user="$(id -un)"

  # Once privileges have already been dropped, the current process owner is the
  # only safe answer. Preserved SUDO_USER/DOAS_USER values can otherwise point
  # back to root and break per-user paths like /run/user/<uid>.
  if [[ "$current_uid" -ne 0 ]]; then
    printf '%s\n' "$current_user"
    return 0
  fi

  for candidate in "${SUDO_USER:-}" "${DOAS_USER:-}"; do
    if [[ -n "$candidate" && "$candidate" != "root" ]] && id -u "$candidate" >/dev/null 2>&1; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done

  if [[ -n "${PKEXEC_UID:-}" && "${PKEXEC_UID}" =~ ^[0-9]+$ ]]; then
    candidate="$(id -nu "${PKEXEC_UID}" 2>/dev/null || true)"
    if [[ -n "$candidate" && "$candidate" != "root" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  fi

  candidate="$(logname 2>/dev/null || true)"
  if [[ -n "$candidate" && "$candidate" != "root" ]] && id -u "$candidate" >/dev/null 2>&1; then
    printf '%s\n' "$candidate"
    return 0
  fi

  printf '%s\n' "$current_user"
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
  local uid current_uid
  current_uid="$(id -u)"
  uid="$(id -u "$real_user")"

  if [[ "$uid" -eq "$current_uid" && -n "${XDG_RUNTIME_DIR:-}" ]]; then
    printf '%s\n' "$XDG_RUNTIME_DIR"
    return 0
  fi

  printf '/run/user/%s\n' "$uid"
}

# --- Execution Wrappers ---
# Runs a command as the real user, ensuring correct environment variables (like DBUS and XDG)
run_as_user() {
  local real_user
  real_user="$(get_real_user)"
  
  if [[ "$(id -u)" -eq 0 && "$real_user" != "$(id -un)" ]]; then
    local uid
    local user_home
    uid="$(id -u "$real_user")"
    user_home="$(get_user_home "$real_user")"
    sudo -E -u "$real_user" \
      HOME="$user_home" \
      XDG_CONFIG_HOME="$user_home/.config" \
      XDG_DATA_HOME="$user_home/.local/share" \
      XDG_CACHE_HOME="$user_home/.cache" \
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
# Glyph-prefixed, consistent with `mdots sync` output. When invoked as a mdots
# hook, mdots exports MDOTS_LOG_INDENT so these lines align under its detail
# column; standalone the variable is unset and the lines start at the margin.
log_info() { echo -e "${MDOTS_LOG_INDENT:-}\033[0;36m→\033[0m $*"; }
log_success() { echo -e "${MDOTS_LOG_INDENT:-}\033[0;32m✓\033[0m $*"; }
log_warn() { echo -e "${MDOTS_LOG_INDENT:-}\033[1;33m⚠\033[0m $*" >&2; }
log_error() { echo -e "${MDOTS_LOG_INDENT:-}\033[0;31m✗\033[0m $*" >&2; }
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
  mkdir -p "$CACHY_RUNTIME" >/dev/null 2>&1 || true
  chmod 0700 "$CACHY_RUNTIME" >/dev/null 2>&1 || true
fi
