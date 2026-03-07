#!/usr/bin/env bash
set -e

# Repository root (this script lives at modules/user-services/scripts/enable.sh)
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/../../.." && pwd)"

# Source the core DCLI library
source "$REPO_ROOT/modules/base/lib/core.sh"

# Define services
services=(
  mpd.service
  fusuma.service
  hyprland-polkit-agent.service
  hypr-nm-applet.service
  niri-nm-applet.service
  niri-blueman-applet.service
  niri-snapper-tools-check.service
  hypr-clip-persist.service
  hypr-init.service
  stasis.timer
  walker.timer
  flatpak-managed-install.timer
  hyprland-bt-autoconnect.timer
  niri-bt-autoconnect.timer
  niri-bt-autoconnect.service
  kdeconnect.timer
  noctalia.service
  niri-bootstrap.service
  niri-sticky.service
  niri-niriswitcher.service
  niri-polkit-agent.service
  copyq.service
  ppp-auto-profile.timer
  elephant.service
  transmission.service
)

echo "Enabling user services for user: $REAL_USER..."

# Ensure MPD uses user-scoped config, not /etc/mpd.conf (/var/lib/mpd)
safe_install \
  "$REPO_ROOT/modules/mpd/dotfiles/mpd/mpd.conf" \
  "$USER_HOME/.config/mpd/mpd.conf"
safe_install \
  "$REPO_ROOT/modules/mpd/dotfiles/systemd/user/mpd.service" \
  "$USER_HOME/.config/systemd/user/mpd.service"

# Ensure ppp auto-profile units exist before enable pass.
safe_install \
  "$REPO_ROOT/modules/niri/dotfiles/systemd/user/ppp-auto-profile.service" \
  "$USER_HOME/.config/systemd/user/ppp-auto-profile.service"
safe_install \
  "$REPO_ROOT/modules/niri/dotfiles/systemd/user/ppp-auto-profile.timer" \
  "$USER_HOME/.config/systemd/user/ppp-auto-profile.timer"

run_as_user systemctl --user daemon-reload >/dev/null 2>&1 || true

for s in "${services[@]}"; do
  # Check if service exists
  if run_as_user systemctl --user list-unit-files "$s" >/dev/null 2>&1; then
    run_as_user systemctl --user enable "$s"
    echo "  -> Enabled $s"
  else
    echo "  -> Skipped $s (not found or user bus inaccessible)"
  fi
done

# PipeWire stacks often pull compatibility references to legacy user units.
# Mask them to avoid not-found noise in `systemctl --user list-units --all`.
if run_as_user systemctl --user list-unit-files pipewire-pulse.service >/dev/null 2>&1; then
  for legacy in pulseaudio.service pipewire-media-session.service; do
    run_as_user systemctl --user stop "$legacy" >/dev/null 2>&1 || true
    run_as_user systemctl --user mask "$legacy" >/dev/null 2>&1 || true
    echo "  -> Masked $legacy (PipeWire compatibility)"
  done
fi
