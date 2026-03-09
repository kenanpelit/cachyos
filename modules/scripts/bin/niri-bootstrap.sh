#!/usr/bin/env bash
# ==============================================================================
# Script: niri-bootstrap.sh
# Description: Standardized bootstrap for Niri session.
# Usage: niri-bootstrap.sh
# ==============================================================================

set -eEuo pipefail

log() { printf "[niri-bootstrap] %s\n" "$*"; }
warn() { printf "[niri-bootstrap] WARN: %s\n" "$*" >&2; }

# Turbo: Removed artificial delay, relying on service dependencies
# Ensure PATH includes local bin
export PATH="$HOME/.local/bin:$PATH"

# Minimal readiness check before calling osc
wait_for_socket() {
  local i
  for i in $(seq 1 100); do
    [[ -S "$NIRI_SOCKET" ]] && return 0
    sleep 0.05
  done
  return 1
}

if command -v niri-osc >/dev/null 2>&1; then
  # NIRI_SOCKET is usually exported by niri itself or niri-osc set env
  if [[ -n "${NIRI_SOCKET:-}" ]]; then
    wait_for_socket || warn "Socket not found, attempting anyway..."
  fi

  if ! niri-osc set init; then
    warn "niri-osc set init failed"
    exit 1
  fi
else
  warn "niri-osc not found"
  exit 1
fi

exit 0
