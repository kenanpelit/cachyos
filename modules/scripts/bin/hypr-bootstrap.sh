#!/usr/bin/env bash
# ==============================================================================
# Script: hypr-bootstrap
# Description: Early Hyprland bootstrap for monitor/workspace normalization and
#              audio defaults.
# Usage: hypr-bootstrap
# ==============================================================================

set -euo pipefail

LOG_TAG="hypr-bootstrap"

log() { printf '[%s] %s\n' "$LOG_TAG" "$*"; }
warn() { printf '[%s] WARN: %s\n' "$LOG_TAG" "$*" >&2; }

export PATH="$HOME/.local/bin:$HOME/bin:/usr/local/bin:/usr/bin:/bin:${PATH:-}"

ensure_hypr_env() {
  : "${XDG_RUNTIME_DIR:="/run/user/$(id -u)"}"

  if [[ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]]; then
    return 0
  fi

  local sig
  sig="$(ls "$XDG_RUNTIME_DIR"/hypr 2>/dev/null | head -n1 || true)"
  if [[ -n "${sig:-}" ]]; then
    export HYPRLAND_INSTANCE_SIGNATURE="$sig"
  fi
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

  run_if_present hypr-osc switch
  run_if_present osc-soundctl init

  log "hypr-bootstrap completed."
}

main
