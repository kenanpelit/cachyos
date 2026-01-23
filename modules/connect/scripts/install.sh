#!/usr/bin/env bash
set -euo pipefail

if command -v systemctl >/dev/null 2>&1; then
  systemctl --user daemon-reload >/dev/null 2>&1 || true
  systemctl --user enable --now kdeconnect.service kdeconnect-indicator.service >/dev/null 2>&1 || true
fi
