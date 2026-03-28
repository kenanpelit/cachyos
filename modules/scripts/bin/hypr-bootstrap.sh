#!/usr/bin/env bash
# ==============================================================================
# Script: hypr-bootstrap
# Description: Early Hyprland bootstrap stage.
# Usage: hypr-bootstrap
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMMON_HELPER="${SCRIPT_DIR}/hypr-session-common.sh"
[[ -r "${COMMON_HELPER}" ]] || COMMON_HELPER="${SCRIPT_DIR}/hypr-session-common"
# shellcheck source=hypr-session-common.sh
source "${COMMON_HELPER}"

LOG_TAG="hypr-bootstrap"

log() { printf '[%s] %s\n' "$LOG_TAG" "$*"; }
warn() { printf '[%s] WARN: %s\n' "$LOG_TAG" "$*" >&2; }

export PATH="$HOME/.local/bin:$HOME/bin:/usr/local/bin:/usr/bin:/bin:${PATH:-}"

ensure_hypr_env() {
  hypr_ensure_runtime_dir
  hypr_detect_instance_signature
}

wait_for_hyprctl() {
  local i
  for i in $(seq 1 120); do
    if command -v hyprctl >/dev/null 2>&1 && hyprctl version >/dev/null 2>&1; then
      return 0
    fi
    sleep 0.1
  done
  return 1
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

  if ! wait_for_hyprctl; then
    warn "hyprctl did not become ready in time; continuing"
  fi

  if [[ -z "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]]; then
    warn "HYPRLAND_INSTANCE_SIGNATURE is unset; continuing anyway"
  fi

  log "hypr-bootstrap completed."
}

main
