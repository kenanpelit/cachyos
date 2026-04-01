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

workspace_name_from_slot() {
  local workspace_ref="${1:-}"
  local here_file="${XDG_CONFIG_HOME:-$HOME/.config}/niri/runtime/workspace-here.tsv"

  [[ -n "${workspace_ref}" ]] || return 1
  [[ "${workspace_ref}" =~ ^[0-9]+$ ]] || {
    printf '%s\n' "${workspace_ref}"
    return 0
  }
  [[ -f "${here_file}" ]] || {
    printf '%s\n' "${workspace_ref}"
    return 0
  }

  awk -F '\t' -v slot="${workspace_ref}" '
    BEGIN { found = 0 }
    /^[[:space:]]*#/ { next }
    $1 == slot && $2 != "" {
      print $2
      found = 1
      exit 0
    }
    END { exit found ? 0 : 1 }
  ' "${here_file}" 2>/dev/null || printf '%s\n' "${workspace_ref}"
}

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
      focus_ws="$(workspace_name_from_slot "${focus_ws}")"
      if niri-osc set go --focus "ws:${focus_ws}"; then
        log "arranged windows and focused ws:${focus_ws}"
      else
        warn "arrangement helper failed; continuing without blocking startup"
      fi
    else
      if niri-osc set go; then
        log "arranged windows"
      else
        warn "arrangement helper failed; continuing without blocking startup"
      fi
    fi
    exit 0
  fi

  if [[ "${NIRI_INIT_SKIP_FOCUS_WORKSPACE:-0}" != "1" ]]; then
    local focus_ws
    focus_ws="${NIRI_INIT_FOCUS_WORKSPACE:-2}"
    focus_ws="$(workspace_name_from_slot "${focus_ws}")"
    if niri msg action focus-workspace "${focus_ws}" >/dev/null 2>&1; then
      log "focused workspace ${focus_ws}"
    else
      warn "failed to focus workspace ${focus_ws}"
    fi
  fi
}

main
