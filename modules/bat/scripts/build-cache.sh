#!/usr/bin/env bash
set -euo pipefail

if command -v bat >/dev/null 2>&1; then
  bat cache --build >/dev/null 2>&1 || true
elif command -v batcat >/dev/null 2>&1; then
  batcat cache --build >/dev/null 2>&1 || true
fi
