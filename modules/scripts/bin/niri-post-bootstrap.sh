#!/usr/bin/env bash
# ==============================================================================
# Script: niri-post-bootstrap
# Description: Late Niri session polish for desktop settings and ready notification.
# Usage: niri-post-bootstrap
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMMON_HELPER="${SCRIPT_DIR}/niri-session-common.sh"
[[ -r "${COMMON_HELPER}" ]] || COMMON_HELPER="${SCRIPT_DIR}/niri-session-common"
# shellcheck source=niri-session-common.sh
source "${COMMON_HELPER}"

LOG_TAG="niri-post-bootstrap"

log() { printf '[%s] %s\n' "$LOG_TAG" "$*" >&2; }
warn() { printf '[%s] WARN: %s\n' "$LOG_TAG" "$*" >&2; }

export PATH="$HOME/.local/bin:$HOME/bin:/usr/local/bin:/usr/bin:/bin:${PATH:-}"

ensure_niri_env() {
  niri_ensure_runtime_dir
  niri_ensure_session_identity
  niri_detect_wayland_display
  niri_detect_socket
}

run_if_present() {
  local cmd="$1"
  shift || true

  if command -v "$cmd" >/dev/null 2>&1; then
    if "$cmd" "$@"; then
      log "$cmd $*"
    else
      warn "$cmd $* failed; continuing"
    fi
  else
    warn "$cmd not found; skipping"
  fi
}

main() {
  ensure_niri_env || true

  if command -v notify-send >/dev/null 2>&1; then
    notify-send -t 1800 "Niri" "Session ready" >/dev/null 2>&1 || true
  fi

  log "niri-post-bootstrap completed"
}

main
