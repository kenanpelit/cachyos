#!/usr/bin/env bash
set -e

# Detect real user
if [ -n "${SUDO_USER:-}" ]; then
  REAL_USER="$SUDO_USER"
else
  REAL_USER="$(whoami)"
fi

# Define services
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

echo "Enabling user services for user: $REAL_USER..."

# Function to run command as real user
run_as_user() {
  if [ "$REAL_USER" != "$(whoami)" ]; then
    # Preserve XDG_RUNTIME_DIR for systemctl --user to work
    USER_ID=$(id -u "$REAL_USER")
    export XDG_RUNTIME_DIR="/run/user/$USER_ID"
    
    # Run using sudo -u with explicit env
    sudo -E -u "$REAL_USER" XDG_RUNTIME_DIR="/run/user/$USER_ID" DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$USER_ID/bus" "$@"
  else
    "$@"
  fi
}

for s in "${services[@]}"; do
  # Check if service exists
  if run_as_user systemctl --user list-unit-files "$s" >/dev/null 2>&1; then
    run_as_user systemctl --user enable --now "$s"
    echo "  -> Enabled $s"
  else
    echo "  -> Skipped $s (not found or user bus inaccessible)"
  fi
done
