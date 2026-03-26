#!/usr/bin/env bash
# ==============================================================================
# Script: niri-bootstrap
# Description: Standardized bootstrap for Niri session.
# Usage: niri-bootstrap
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMMON_HELPER="${SCRIPT_DIR}/niri-session-common.sh"
[[ -r "${COMMON_HELPER}" ]] || COMMON_HELPER="${SCRIPT_DIR}/niri-session-common"
# shellcheck source=niri-session-common.sh
source "${COMMON_HELPER}"

log() { printf '[niri-bootstrap] %s\n' "$*"; }
warn() { printf '[niri-bootstrap] WARN: %s\n' "$*" >&2; }

export PATH="$HOME/.local/bin:$HOME/bin:/usr/local/bin:/usr/bin:/bin:${PATH:-}"

ensure_niri_env() {
  niri_ensure_runtime_dir
  niri_ensure_session_identity
  niri_detect_wayland_display
  niri_detect_socket
}

wait_for_socket() {
  local _
  for _ in $(seq 1 120); do
    niri_detect_socket
    [[ -n "${NIRI_SOCKET:-}" && -S "${NIRI_SOCKET}" ]] && return 0
    sleep 0.1
  done
  return 1
}

main() {
  ensure_niri_env || true

  if ! wait_for_socket; then
    warn "NIRI_SOCKET did not become ready in time; continuing"
  fi

  if ! command -v niri-osc >/dev/null 2>&1; then
    warn "niri-osc not found"
    exit 1
  fi

  if ! niri-osc set init; then
    warn "niri-osc set init failed"
    exit 1
  fi

  log "niri-bootstrap completed."
}

main
