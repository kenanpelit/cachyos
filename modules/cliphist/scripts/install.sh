#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
source "$REPO_ROOT/modules/base/lib/core.sh"

if ! command -v systemctl >/dev/null 2>&1; then
  exit 0
fi

run_as_user systemctl --user daemon-reload >/dev/null 2>&1 || true

# Noctalia's clipper owns the live cliphist ingestion pipeline. Keeping a
# second wl-paste watcher here duplicates work and has been leaving the unit
# in a dead state under Hyprland.
run_as_user systemctl --user disable --now cliphist.service >/dev/null 2>&1 || true
run_as_user systemctl --user stop cliphist.service >/dev/null 2>&1 || true
run_as_user systemctl --user reset-failed cliphist.service >/dev/null 2>&1 || true
run_as_user rm -f "$USER_HOME/.config/systemd/user/default.target.wants/cliphist.service" || true
run_as_user rm -f "$USER_HOME/.config/systemd/user/graphical-session.target.wants/cliphist.service" || true
