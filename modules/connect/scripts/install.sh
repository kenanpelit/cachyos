#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
MODULE_DIR="$(cd -- "$SCRIPT_DIR/.." && pwd)"
SYSTEMD_DIR="$MODULE_DIR/dotfiles/systemd/user"
USER_SYSTEMD_DIR="$HOME/.config/systemd/user"
GRAPHICAL_WANTS_DIR="$USER_SYSTEMD_DIR/graphical-session.target.wants"
DEFAULT_WANTS_DIR="$USER_SYSTEMD_DIR/default.target.wants"

if command -v systemctl >/dev/null 2>&1; then
  if [[ -f "$HOME/.local/bin/kdeconnectd-wrapper" ]]; then
    chmod +x "$HOME/.local/bin/kdeconnectd-wrapper" || true
  fi

  mkdir -p "$USER_SYSTEMD_DIR" "$GRAPHICAL_WANTS_DIR" "$DEFAULT_WANTS_DIR"
  ln -snf "$SYSTEMD_DIR/kdeconnect.service" "$USER_SYSTEMD_DIR/kdeconnect.service"
  ln -snf "$SYSTEMD_DIR/kdeconnect.timer" "$USER_SYSTEMD_DIR/kdeconnect.timer"
  ln -snf "$SYSTEMD_DIR/kdeconnect-indicator.service" "$USER_SYSTEMD_DIR/kdeconnect-indicator.service"

  # Keep KDE Connect tied to graphical-session.target only; a default.target
  # enablement can start graphical-session.target before the compositor is ready
  # and break UWSM logins.
  rm -f "$DEFAULT_WANTS_DIR/kdeconnect.timer"
  ln -snf "$USER_SYSTEMD_DIR/kdeconnect.timer" "$GRAPHICAL_WANTS_DIR/kdeconnect.timer"

  systemctl --user daemon-reload >/dev/null 2>&1 || true
  systemctl --user start kdeconnect.timer >/dev/null 2>&1 || true
fi
