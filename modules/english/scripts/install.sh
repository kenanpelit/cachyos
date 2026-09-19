#!/usr/bin/env bash
set -euo pipefail

if command -v systemctl >/dev/null 2>&1; then
  systemctl --user daemon-reload >/dev/null 2>&1 || true
  # The dev server is not started at login: `start-eng` starts english-dev.service on demand.
fi
