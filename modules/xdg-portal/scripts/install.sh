#!/usr/bin/env bash
set -euo pipefail

if command -v systemctl >/dev/null 2>&1; then
  systemctl --user daemon-reload >/dev/null 2>&1 || true
  # Enable the delayed orchestration timer
  systemctl --user enable --now xdg-desktop-portal-delayed.timer >/dev/null 2>&1 || true
fi
