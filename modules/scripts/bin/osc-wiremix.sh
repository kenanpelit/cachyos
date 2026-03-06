#!/usr/bin/env bash
# ==============================================================================
# Script: osc-wiremix.sh
# Description: Launch wiremix in kitty with stable class/app-id
# Usage: osc-wiremix.sh [options]
# ==============================================================================
set -euo pipefail

# Launch wiremix in kitty with a stable class/app-id for compositor rules.

need() { command -v "$1" >/dev/null 2>&1; }
die() { echo "ERROR: $*" >&2; exit 1; }

need wiremix || die "wiremix not found (install package: wiremix)"
need kitty || die "kitty not found"

exec kitty --class wiremix -T wiremix --single-instance -e wiremix "$@"
