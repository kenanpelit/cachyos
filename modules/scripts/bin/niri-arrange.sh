#!/usr/bin/env bash
# ==============================================================================
# Script: niri-arrange
# Description: Tracked initial workspace arrangement for the Niri session.
# Usage: niri-arrange
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMMON_HELPER="${SCRIPT_DIR}/niri-session-common.sh"
[[ -r "${COMMON_HELPER}" ]] || COMMON_HELPER="${SCRIPT_DIR}/niri-session-common"
# shellcheck source=niri-session-common.sh
source "${COMMON_HELPER}"

LOG_TAG="niri-arrange"

log() { printf '[%s] %s\n' "$LOG_TAG" "$*" >&2; }
warn() { printf '[%s] WARN: %s\n' "$LOG_TAG" "$*" >&2; }

export PATH="$HOME/.local/bin:$HOME/bin:/usr/local/bin:/usr/bin:/bin:${PATH:-}"

ensure_niri_env() {
  niri_ensure_runtime_dir
  niri_ensure_session_identity
  niri_detect_wayland_display
  niri_detect_socket
}

main() {
  ensure_niri_env || true

  if ! command -v niri >/dev/null 2>&1; then
    warn "niri not found; skipping arrangement"
    exit 0
  fi

  if ! niri msg version >/dev/null 2>&1; then
    warn "cannot connect to niri; skipping arrangement"
    exit 0
  fi

  if [[ "${NIRI_INIT_SKIP_ARRANGE:-0}" != "1" ]]; then
    if [[ "${NIRI_INIT_SKIP_FOCUS_WORKSPACE:-0}" != "1" ]]; then
      local focus_ws
      focus_ws="${NIRI_INIT_FOCUS_WORKSPACE:-2}"
      niri-osc go --focus "ws:${focus_ws}"
      log "arranged windows and focused ws:${focus_ws}"
    else
      niri-osc go
      log "arranged windows"
    fi
    exit 0
  fi

  if [[ "${NIRI_INIT_SKIP_FOCUS_WORKSPACE:-0}" != "1" ]]; then
    local focus_ws
    focus_ws="${NIRI_INIT_FOCUS_WORKSPACE:-2}"
    if niri msg action focus-workspace "${focus_ws}" >/dev/null 2>&1; then
      log "focused workspace ${focus_ws}"
    else
      warn "failed to focus workspace ${focus_ws}"
    fi
  fi
}

main
