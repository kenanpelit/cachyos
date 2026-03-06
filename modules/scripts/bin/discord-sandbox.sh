#!/usr/bin/env bash
# ==============================================================================
# Script: discord-sandbox.sh
# Description: Launches Discord with sandbox disabled to avoid common issues.
# Usage: discord-sandbox.sh [options]
# ==============================================================================
set -euo pipefail

if ! command -v discord >/dev/null 2>&1; then
  echo "discord-sandbox: 'discord' not found in PATH" >&2
  exit 127
fi

exec discord --no-sandbox --disable-gpu-sandbox "$@"
