#!/usr/bin/env bash
set -e

# Detect real user
if [ -n "${SUDO_USER:-}" ]; then
  REAL_USER="$SUDO_USER"
else
  REAL_USER="$(whoami)"
fi

USER_HOME="$(getent passwd "$REAL_USER" | cut -d: -f6 2>/dev/null || true)"
if [ -z "${USER_HOME:-}" ]; then
  USER_HOME="$(eval echo "~$REAL_USER")"
fi

# Repository root (this script lives at modules/user-services/scripts/enable.sh)
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/../../.." && pwd)"

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
  niri-bootstrap.service
  transmission.service
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

# Idempotent install (avoids "are the same file" errors when dotfiles are symlinked)
safe_install() {
  local src="$1"
  local dst="$2"
  local mode="${3:-644}"

  [ -f "$src" ] || return 0
  if [ -e "$dst" ] && [ "$src" -ef "$dst" ]; then
    return 0
  fi

  run_as_user install -Dm"$mode" -- "$src" "$dst"
}

# Ensure MPD uses user-scoped config, not /etc/mpd.conf (/var/lib/mpd)
safe_install \
  "$REPO_ROOT/modules/mpd/dotfiles/mpd/mpd.conf" \
  "$USER_HOME/.config/mpd/mpd.conf"
safe_install \
  "$REPO_ROOT/modules/mpd/dotfiles/systemd/user/mpd.service" \
  "$USER_HOME/.config/systemd/user/mpd.service"

run_as_user systemctl --user daemon-reload >/dev/null 2>&1 || true

for s in "${services[@]}"; do
  # Check if service exists
  if run_as_user systemctl --user list-unit-files "$s" >/dev/null 2>&1; then
    run_as_user systemctl --user enable --now "$s"
    echo "  -> Enabled $s"
  else
    echo "  -> Skipped $s (not found or user bus inaccessible)"
  fi
done
