#!/usr/bin/env bash
# ==============================================================================
# Script: mango-post-bootstrap
# Description: Late MangoWM session polish and ready notification.
# Usage: mango-post-bootstrap
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMMON_HELPER="${SCRIPT_DIR}/mango-session-common.sh"
[[ -r "${COMMON_HELPER}" ]] || COMMON_HELPER="${SCRIPT_DIR}/mango-session-common"
# shellcheck source=mango-session-common.sh
source "${COMMON_HELPER}"

LOG_TAG="mango-post-bootstrap"

log() { printf '[%s] %s\n' "$LOG_TAG" "$*" >&2; }

export PATH="$HOME/.local/bin:$HOME/bin:/usr/local/bin:/usr/bin:/bin:${PATH:-}"

main() {
  mango_ensure_runtime_dir
  mango_ensure_session_identity
  mango_detect_wayland_display

  if command -v notify-send >/dev/null 2>&1; then
    notify-send -t 1800 "MangoWM" "Session ready" >/dev/null 2>&1 || true
  fi

  log "mango-post-bootstrap completed."
}

main
