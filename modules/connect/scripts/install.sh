#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
MODULE_DIR="$(cd -- "$SCRIPT_DIR/.." && pwd)"
REPO_ROOT="$(cd -- "${MODULE_DIR}/../.." && pwd)"

# shellcheck source=/dev/null
source "${REPO_ROOT}/modules/base/lib/core.sh"

SYSTEMD_DIR="$MODULE_DIR/dotfiles/systemd/user"
USER_SYSTEMD_DIR="$USER_HOME/.config/systemd/user"
GRAPHICAL_WANTS_DIR="$USER_SYSTEMD_DIR/graphical-session.target.wants"
DEFAULT_WANTS_DIR="$USER_SYSTEMD_DIR/default.target.wants"
AUTOSTART_DIR="$USER_HOME/.config/autostart"

if command -v systemctl >/dev/null 2>&1; then
  run_as_user mkdir -p "$USER_SYSTEMD_DIR" "$GRAPHICAL_WANTS_DIR" "$DEFAULT_WANTS_DIR" "$AUTOSTART_DIR"

  # Clean up the previous KDE Connect-managed path so only Valent remains.
  run_as_user systemctl --user stop kdeconnect-indicator.service kdeconnect.service kdeconnect.timer >/dev/null 2>&1 || true
  run_as_user rm -f \
    "$USER_HOME/.local/bin/kdeconnectd-wrapper" \
    "$USER_SYSTEMD_DIR/kdeconnect.service" \
    "$USER_SYSTEMD_DIR/kdeconnect.timer" \
    "$USER_SYSTEMD_DIR/kdeconnect-indicator.service" \
    "$GRAPHICAL_WANTS_DIR/kdeconnect.timer" \
    "$DEFAULT_WANTS_DIR/kdeconnect.timer" \
    "$AUTOSTART_DIR/org.kde.kdeconnect.daemon.desktop"

  run_as_user ln -sfn "$SYSTEMD_DIR/valent.service" "$USER_SYSTEMD_DIR/valent.service"
  run_as_user ln -sfn "$SYSTEMD_DIR/valent.timer" "$USER_SYSTEMD_DIR/valent.timer"

  # Keep Valent tied to graphical-session.target only; a default.target
  # enablement can start graphical-session.target too early and break UWSM.
  run_as_user rm -f "$DEFAULT_WANTS_DIR/valent.timer"
  run_as_user ln -sfn "$USER_SYSTEMD_DIR/valent.timer" "$GRAPHICAL_WANTS_DIR/valent.timer"

  # Valent's SFTP integration expects the GCR SSH agent socket path.
  run_as_user systemctl --user enable --now gcr-ssh-agent.socket >/dev/null 2>&1 || true

  run_as_user systemctl --user daemon-reload >/dev/null 2>&1 || true
  run_as_user systemctl --user start valent.timer >/dev/null 2>&1 || true
fi
