#!/usr/bin/env bash
# ==============================================================================
# Script: mango-layer-audit
# Description: Inspect MangoWM layer-shell names for layer rule tuning.
# Usage: mango-layer-audit [--once|--watch] [--duration SECONDS]
# ==============================================================================

set -euo pipefail

MODE="once"
DURATION="${MANGO_LAYER_AUDIT_DURATION:-20}"

usage() {
  cat <<'EOF'
Usage: mango-layer-audit [--once|--watch] [--duration SECONDS]

Prints the last/focused Mango layer names reported by mmsg. Use --watch while
opening Noctalia panels, launchers, screenshots, notifications, and OSDs.
EOF
}

while (($#)); do
  case "$1" in
  --once)
    MODE="once"
    shift
    ;;
  --watch)
    MODE="watch"
    shift
    ;;
  --duration)
    DURATION="$2"
    shift 2
    ;;
  -h | --help | help)
    usage
    exit 0
    ;;
  *)
    usage >&2
    exit 2
    ;;
  esac
done

command -v mmsg >/dev/null 2>&1 || {
  echo "mmsg is required" >&2
  exit 1
}

case "$MODE" in
once)
  mmsg -g -e
  ;;
watch)
  if command -v timeout >/dev/null 2>&1; then
    timeout "$DURATION" mmsg -w -e
  else
    mmsg -w -e
  fi
  ;;
esac
