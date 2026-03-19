#!/usr/bin/env bash
# ==============================================================================
# Script: hypr-post-bootstrap
# Description: Late Hyprland session polish for desktop settings and cursor sync.
# Usage: hypr-post-bootstrap
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMMON_HELPER="${SCRIPT_DIR}/hypr-session-common.sh"
[[ -r "${COMMON_HELPER}" ]] || COMMON_HELPER="${SCRIPT_DIR}/hypr-session-common"
# shellcheck source=hypr-session-common.sh
source "${COMMON_HELPER}"

LOG_TAG="hypr-post-bootstrap"

log() { printf '[%s] %s\n' "$LOG_TAG" "$*"; }
warn() { printf '[%s] WARN: %s\n' "$LOG_TAG" "$*" >&2; }

export PATH="$HOME/.local/bin:$HOME/bin:/usr/local/bin:/usr/bin:/bin:${PATH:-}"

ensure_hypr_env() {
  hypr_ensure_runtime_dir
  hypr_detect_instance_signature
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
  ensure_hypr_env || true

  if command -v hyprctl >/dev/null 2>&1; then
    if hyprctl setcursor "${XCURSOR_THEME:-capitaine-cursors}" "${XCURSOR_SIZE:-24}" >/dev/null 2>&1; then
      log "hyprctl setcursor ${XCURSOR_THEME:-capitaine-cursors} ${XCURSOR_SIZE:-24}"
    else
      warn "hyprctl setcursor failed; continuing"
    fi
  else
    warn "hyprctl not found; skipping cursor sync"
  fi

  log "hypr-post-bootstrap completed."
}

main
