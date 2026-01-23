#!/usr/bin/env bash
set -euo pipefail

mkdir -p "$HOME/.local/share/dbus-1/services"

# Ensure systemd sees units and (optionally) enable them.
if command -v systemctl >/dev/null 2>&1; then
  systemctl --user daemon-reload >/dev/null 2>&1 || true
  systemctl --user enable --now elephant.service walker.service >/dev/null 2>&1 || true
fi
