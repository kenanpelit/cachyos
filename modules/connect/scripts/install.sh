#!/usr/bin/env bash
set -euo pipefail

if command -v systemctl >/dev/null 2>&1; then
  if [[ -f "$HOME/.local/bin/kdeconnectd-wrapper" ]]; then
    chmod +x "$HOME/.local/bin/kdeconnectd-wrapper" || true
  fi
  systemctl --user daemon-reload >/dev/null 2>&1 || true
  systemctl --user enable --now kdeconnect.service kdeconnect-indicator.service >/dev/null 2>&1 || true
fi
