#!/usr/bin/env bash
set -euo pipefail

# Backward-compatible wrapper.
# New canonical entrypoint is: power-profile

if command -v power-profile >/dev/null 2>&1; then
  exec power-profile toggle "$@"
fi

echo "ERROR: power-profile not found in PATH" >&2
exit 1
