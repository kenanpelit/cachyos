#!/usr/bin/env bash
set -euo pipefail

if command -v pkgfile >/dev/null 2>&1; then
  pkgfile -u || true
fi
