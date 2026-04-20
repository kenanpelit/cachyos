#!/usr/bin/env bash
# ==============================================================================
# Script: mango-session-refresh
# Description: Refresh MangoWM session environment and rerun bootstrap hooks.
# Usage: mango-session-refresh
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMMON_HELPER="${SCRIPT_DIR}/mango-session-common.sh"
[[ -r "${COMMON_HELPER}" ]] || COMMON_HELPER="${SCRIPT_DIR}/mango-session-common"
# shellcheck source=mango-session-common.sh
source "${COMMON_HELPER}"

main() {
  mango_ensure_runtime_dir
  mango_load_session_env
  mango_normalize_session_paths
  mango_detect_wayland_display
  session_common_detect_x11_display
  mango_ensure_session_identity
  mango_sync_session_environment
  mango_sync_runtime_environment

  if command -v systemctl >/dev/null 2>&1; then
    systemctl --user start --no-block \
      mango-session-env.service \
      mango-bootstrap.service \
      mango-arrange.service \
      mango-post-bootstrap.service >/dev/null 2>&1 || true
  fi
}

main "$@"
