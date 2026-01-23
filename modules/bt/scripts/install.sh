#!/usr/bin/env bash
set -euo pipefail

if command -v systemctl >/dev/null 2>&1; then
  systemctl --user daemon-reload >/dev/null 2>&1 || true
  # Enable timers (best-effort)
  systemctl --user enable --now hyprland-bt-autoconnect.timer niri-bt-autoconnect.timer >/dev/null 2>&1 || true
fi
