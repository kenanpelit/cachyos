#!/usr/bin/env bash
set -e

# Enable and start user services
services=(
  mpd.service
  fusuma.service
  kdeconnect.service
  kdeconnect-indicator.service
  ollama.service
  stasis.service
  flatpak-managed-install.timer
  hyprland-bt-autoconnect.timer
  niri-bt-autoconnect.timer
)

echo "Enabling user services..."
for s in "${services[@]}"; do
  # Check if service file exists before enabling to avoid errors
  if systemctl --user list-unit-files "$s" >/dev/null 2>&1; then
    systemctl --user enable --now "$s"
    echo "  -> Enabled $s"
  else
    echo "  -> Skipped $s (not found)"
  fi
done
