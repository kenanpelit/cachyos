#!/usr/bin/env bash
# ==============================================================================
# Script: mango-bootstrap
# Description: Early MangoWM bootstrap stage.
# Usage: mango-bootstrap
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMMON_HELPER="${SCRIPT_DIR}/mango-session-common.sh"
[[ -r "${COMMON_HELPER}" ]] || COMMON_HELPER="${SCRIPT_DIR}/mango-session-common"
# shellcheck source=mango-session-common.sh
source "${COMMON_HELPER}"

LOG_TAG="mango-bootstrap"

log() { printf '[%s] %s\n' "$LOG_TAG" "$*"; }
warn() { printf '[%s] WARN: %s\n' "$LOG_TAG" "$*" >&2; }

export PATH="$HOME/.local/bin:$HOME/bin:/usr/local/bin:/usr/bin:/bin:${PATH:-}"

ensure_mango_env() {
  mango_ensure_runtime_dir
  mango_ensure_session_identity
  mango_detect_wayland_display
}

wait_for_ipc() {
  local i
  for i in $(seq 1 120); do
    if command -v mmsg >/dev/null 2>&1 && mmsg -g >/dev/null 2>&1; then
      return 0
    fi
    sleep 0.1
  done
  return 1
}

main() {
  ensure_mango_env || true

  if ! wait_for_ipc; then
    warn "mmsg did not become ready in time; continuing"
  fi

  log "mango-bootstrap completed."
}

main
