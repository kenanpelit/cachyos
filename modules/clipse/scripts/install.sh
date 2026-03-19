#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
source "$REPO_ROOT/modules/base/lib/core.sh"

user_home="${USER_HOME:-$HOME}"
state_home="${XDG_STATE_HOME:-$user_home/.local/state}"
config_home="${user_home}/.config/clipse"

run_as_user mkdir -p "$config_home" "$state_home/clipse"
run_as_user /usr/bin/sh -c ': > "$1"' _ "$state_home/clipse/clipse.log"
run_as_user ln -sf "$state_home/clipse/clipse.log" "$config_home/clipse.log"

if command -v systemctl >/dev/null 2>&1; then
  legacy_unit="$user_home/.config/systemd/user/niri-clipse.service"
  legacy_wants="$user_home/.config/systemd/user/niri-daemons.target.wants/niri-clipse.service"

  run_as_user systemctl --user daemon-reload >/dev/null 2>&1 || true
  run_as_user systemctl --user disable --now niri-clipse.service >/dev/null 2>&1 || true
  run_as_user rm -f "$legacy_unit" "$legacy_wants"
  run_as_user systemctl --user reset-failed clipse.service >/dev/null 2>&1 || true
  if run_as_user systemctl --user is-active graphical-session.target >/dev/null 2>&1; then
    run_as_user systemctl --user start clipse.service >/dev/null 2>&1 || true
  fi
fi
