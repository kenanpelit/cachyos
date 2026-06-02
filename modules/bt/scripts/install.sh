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

  # bt-autoconnect.timer is now bound to per-session targets
  # (hyprland/niri/mango) instead of default.target. Drop the stale
  # catch-all symlink so it stops firing under margo. disable/enable
  # only manage symlinks named in the current [Install] section.
  rm -f "${HOME}/.config/systemd/user/default.target.wants/bt-autoconnect.timer" || true
  rm -f "${HOME}/.config/systemd/user/margo-session.target.wants/bt-autoconnect.timer" || true

  systemctl --user enable --now bt-autoconnect.timer >/dev/null 2>&1 || true
fi
