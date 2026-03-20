#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
source "$REPO_ROOT/modules/base/lib/core.sh"

script_src="$REPO_ROOT/modules/scripts/bin/sunsetr-set.sh"
bin_dir="$USER_HOME/.local/bin"

if [[ ! -f "$script_src" ]]; then
  echo "[sunsetr-install] WARN: source script not found: $script_src" >&2
  exit 0
fi

run_as_user mkdir -p "$bin_dir"
run_as_user ln -sfn "$script_src" "$bin_dir/sunsetr-set"

niri_session_active() {
  run_as_user systemctl --user is-active --quiet niri-session.target \
    || run_as_user systemctl --user is-active --quiet 'wayland-wm@niri\x2dsession.service'
}

if command -v systemctl >/dev/null 2>&1; then
  run_as_user systemctl --user daemon-reload >/dev/null 2>&1 || true

  user_systemd_dir="$USER_HOME/.config/systemd/user"
  rm -f \
    "$user_systemd_dir/niri-sunsetr.service" \
    "$user_systemd_dir/niri-post-daemons.target.wants/niri-sunsetr.service" \
    "$user_systemd_dir/sunsetr.service.d/10-cachy.conf"
  rmdir "$user_systemd_dir/sunsetr.service.d" >/dev/null 2>&1 || true

  if niri_session_active; then
    run_as_user systemctl --user try-restart sunsetr.service >/dev/null 2>&1 || true
    run_as_user systemctl --user try-restart sunsetr-auto-profile.timer >/dev/null 2>&1 || true
    run_as_user systemctl --user start sunsetr-auto-profile.service >/dev/null 2>&1 || true
  else
    run_as_user systemctl --user stop sunsetr-auto-profile.timer sunsetr.service >/dev/null 2>&1 || true
  fi
fi
