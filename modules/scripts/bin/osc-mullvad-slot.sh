#!/usr/bin/env bash
# ==============================================================================
# osc-mullvad-slot - Shortcut wrapper for Mullvad slot recycle
# ==============================================================================
# Runs:
#   ~/.local/bin/osc-mullvad slot recycle
#
# Usage:
#   osc-mullvad-slot [--dry-run]
# ==============================================================================

set -euo pipefail

SCRIPT_NAME="$(basename "$0")"
OSC_MULLVAD_BIN="${OSC_MULLVAD_BIN:-$HOME/.local/bin/osc-mullvad}"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
NC='\033[0m'

usage() {
  cat <<EOF
Usage:
  $SCRIPT_NAME [--dry-run]

Env:
  OSC_MULLVAD_BIN=$OSC_MULLVAD_BIN
EOF
}

log() {
  echo -e "${CYAN}==>${NC} $*"
}

die() {
  echo -e "${RED}ERROR:${NC} $*" >&2
  exit 1
}

main() {
  local dry_run=""
  if [[ "${1:-}" == "--dry-run" ]]; then
    dry_run="--dry-run"
    shift || true
  fi

  [[ $# -eq 0 ]] || {
    usage >&2
    exit 2
  }

  if [[ ! -x "$OSC_MULLVAD_BIN" ]]; then
    if command -v osc-mullvad >/dev/null 2>&1; then
      OSC_MULLVAD_BIN="$(command -v osc-mullvad)"
    else
      die "osc-mullvad not found in PATH and not executable at $OSC_MULLVAD_BIN"
    fi
  fi

  log "Running: osc-mullvad slot ${dry_run:+$dry_run }recycle"
  if "$OSC_MULLVAD_BIN" slot ${dry_run:+$dry_run }recycle; then
    echo -e "${GREEN}OK:${NC} slot recycle completed"
  else
    die "slot recycle failed"
  fi
}

main "$@"
