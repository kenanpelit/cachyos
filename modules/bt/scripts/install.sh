#!/usr/bin/env bash
set -euo pipefail

if command -v systemctl >/dev/null 2>&1; then
  systemctl --user daemon-reload >/dev/null 2>&1 || true
  # Retire compositor-specific units and keep a single shared timer/service.
  systemctl --user disable --now \
    hyprland-bt-autoconnect.timer \
    hyprland-bt-autoconnect.service \
    niri-bt-autoconnect.timer \
    niri-bt-autoconnect.service \
    >/dev/null 2>&1 || true

  systemctl --user enable --now bt-autoconnect.timer >/dev/null 2>&1 || true
fi
