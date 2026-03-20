#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(readlink -f "$SCRIPT_DIR/../../.." 2>/dev/null || cd "$SCRIPT_DIR/../../.." && pwd)"
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

ensure_user_link() {
  local src="$1"
  local dst="$2"
  local current=""

  current="$(run_as_user readlink "$dst" 2>/dev/null || true)"
  if [[ "$current" != "$src" ]]; then
    run_as_user ln -sfn "$src" "$dst"
  fi
}

if command -v systemctl >/dev/null 2>&1; then
  user_systemd_dir="$USER_HOME/.config/systemd/user"
  systemd_dir="$REPO_ROOT/modules/sunsetr/dotfiles/systemd/user"
  niri_wants_dir="$user_systemd_dir/niri-session.target.wants"

  run_as_user mkdir -p "$user_systemd_dir" "$niri_wants_dir"
  ensure_user_link "$systemd_dir/sunsetr.service" "$user_systemd_dir/sunsetr.service"
  ensure_user_link "$systemd_dir/sunsetr-auto-profile.service" "$user_systemd_dir/sunsetr-auto-profile.service"
  ensure_user_link "$systemd_dir/sunsetr-auto-profile.timer" "$user_systemd_dir/sunsetr-auto-profile.timer"

  rm -f \
    "$user_systemd_dir/niri-sunsetr.service" \
    "$user_systemd_dir/niri-post-daemons.target.wants/niri-sunsetr.service" \
    "$user_systemd_dir/graphical-session.target.wants/sunsetr.service" \
    "$user_systemd_dir/graphical-session.target.wants/sunsetr-auto-profile.timer" \
    "$user_systemd_dir/sunsetr.service.d/10-cachy.conf"
  rmdir "$user_systemd_dir/sunsetr.service.d" >/dev/null 2>&1 || true
  ensure_user_link "$user_systemd_dir/sunsetr.service" "$niri_wants_dir/sunsetr.service"
  ensure_user_link "$user_systemd_dir/sunsetr-auto-profile.timer" "$niri_wants_dir/sunsetr-auto-profile.timer"
  run_as_user systemctl --user daemon-reload >/dev/null 2>&1 || true

  if niri_session_active; then
    run_as_user systemctl --user try-restart sunsetr.service >/dev/null 2>&1 || true
    run_as_user systemctl --user try-restart sunsetr-auto-profile.timer >/dev/null 2>&1 || true
    run_as_user systemctl --user start sunsetr-auto-profile.service >/dev/null 2>&1 || true
  else
    run_as_user systemctl --user stop sunsetr-auto-profile.timer sunsetr.service >/dev/null 2>&1 || true
  fi
fi
