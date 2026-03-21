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

if command -v systemctl >/dev/null 2>&1; then
  if [[ -f "$USER_HOME/.local/bin/kdeconnectd-wrapper" ]]; then
    run_as_user chmod +x "$USER_HOME/.local/bin/kdeconnectd-wrapper" || true
  fi

  run_as_user mkdir -p "$USER_SYSTEMD_DIR" "$GRAPHICAL_WANTS_DIR" "$DEFAULT_WANTS_DIR"
  run_as_user ln -sfn "$SYSTEMD_DIR/kdeconnect.service" "$USER_SYSTEMD_DIR/kdeconnect.service"
  run_as_user ln -sfn "$SYSTEMD_DIR/kdeconnect.timer" "$USER_SYSTEMD_DIR/kdeconnect.timer"
  run_as_user ln -sfn "$SYSTEMD_DIR/kdeconnect-indicator.service" "$USER_SYSTEMD_DIR/kdeconnect-indicator.service"

  # Keep KDE Connect tied to graphical-session.target only; a default.target
  # enablement can start graphical-session.target before the compositor is ready
  # and break UWSM logins.
  run_as_user rm -f "$DEFAULT_WANTS_DIR/kdeconnect.timer"
  run_as_user ln -sfn "$USER_SYSTEMD_DIR/kdeconnect.timer" "$GRAPHICAL_WANTS_DIR/kdeconnect.timer"

  run_as_user systemctl --user daemon-reload >/dev/null 2>&1 || true
  run_as_user systemctl --user start kdeconnect.timer >/dev/null 2>&1 || true
fi
