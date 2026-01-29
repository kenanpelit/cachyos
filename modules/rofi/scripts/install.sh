#!/usr/bin/env bash
set -euo pipefail

config_file="${XDG_CONFIG_HOME:-$HOME/.config}/rofi/config.rasi"

if [[ -f "$config_file" ]]; then
  # Remove stale pidfile directive if present
  sed -i '/^[[:space:]]*pid:[[:space:]]*/d' "$config_file"
fi
