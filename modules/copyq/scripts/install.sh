#!/usr/bin/env bash
set -euo pipefail

if ! command -v systemctl >/dev/null 2>&1; then
  exit 0
fi

systemctl --user daemon-reload >/dev/null 2>&1 || true

# CopyQ should follow the graphical session directly; clean up the legacy timer.
systemctl --user disable --now copyq.timer >/dev/null 2>&1 || true
systemctl --user stop copyq.timer >/dev/null 2>&1 || true
systemctl --user reset-failed copyq.timer >/dev/null 2>&1 || true
rm -f "${HOME}/.config/systemd/user/default.target.wants/copyq.timer" || true
rm -f "${HOME}/.config/systemd/user/graphical-session.target.wants/copyq.timer" || true

# CopyQ is now bound to the niri / Hyprland / mango session targets only —
# not graphical-session.target. Drop the stale catch-all symlink so it stops
# being pulled into every session (notably margo, which uses its own
# clipboard). disable/enable won't remove this on its own: disable only
# touches symlinks named in the current [Install] section.
rm -f "${HOME}/.config/systemd/user/graphical-session.target.wants/copyq.service" || true
rm -f "${HOME}/.config/systemd/user/margo-session.target.wants/copyq.service" || true

systemctl --user enable copyq.service >/dev/null 2>&1 || true
systemctl --user try-restart copyq.service >/dev/null 2>&1 || true
systemctl --user start copyq.service >/dev/null 2>&1 || true
