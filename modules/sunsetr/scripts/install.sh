#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
MODULE_DIR="$(cd -- "$SCRIPT_DIR/.." && pwd)"
REPO_ROOT="$(cd -- "$MODULE_DIR/../.." && pwd)"
REPO_ROOT_PHYS="$(cd -- "$MODULE_DIR/../.." && pwd -P)"
source "$REPO_ROOT_PHYS/modules/base/lib/core.sh"

canonical_repo_root() {
  local candidate="${USER_HOME:-$HOME}/.config/arch-config"
  local candidate_phys=""

  candidate_phys="$(readlink -f "$candidate" 2>/dev/null || true)"
  if [[ -n "$candidate_phys" && "$candidate_phys" == "$REPO_ROOT_PHYS" ]]; then
    printf '%s\n' "$candidate"
  else
    printf '%s\n' "$REPO_ROOT"
  fi
}

REPO_ROOT="$(canonical_repo_root)"
scheduler_src="$REPO_ROOT/modules/scripts/bin/sunsetr-scheduler.sh"
scheduler_loop_src="$REPO_ROOT/modules/scripts/bin/sunsetr-scheduler-loop.sh"
bin_dir="$USER_HOME/.local/bin"

if [[ ! -f "$scheduler_src" ]]; then
  echo "[sunsetr-install] WARN: source script not found: $scheduler_src" >&2
  exit 0
fi

if [[ ! -f "$scheduler_loop_src" ]]; then
  echo "[sunsetr-install] WARN: source script not found: $scheduler_loop_src" >&2
  exit 0
fi

run_as_user mkdir -p "$bin_dir"
run_as_user ln -sfn "$scheduler_src" "$bin_dir/sunsetr-scheduler"
run_as_user ln -sfn "$scheduler_loop_src" "$bin_dir/sunsetr-scheduler-loop"

# Margo (the compositor) is deliberately NOT in this list — it ships
# its own built-in `twilight` blue-light filter and must not have
# sunsetr running alongside it (two clients writing the same
# wlr-gamma-control ramp produces a flicker fight). Sunsetr stays as
# the option for niri / Hyprland / mangowm.
supported_wayland_session_active() {
  run_as_user systemctl --user is-active --quiet 'wayland-wm@niri\x2dsession.service' \
    || run_as_user systemctl --user is-active --quiet 'wayland-wm@start\x2dhyprland.service' \
    || run_as_user systemctl --user is-active --quiet 'wayland-wm@mango\x2dsession.service'
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
  graphical_wants_dir="$user_systemd_dir/graphical-session.target.wants"
  niri_wants_dir="$user_systemd_dir/niri-session.target.wants"
  hypr_wants_dir="$user_systemd_dir/hyprland-session.target.wants"
  mango_wants_dir="$user_systemd_dir/mangowm-session.target.wants"

  run_as_user mkdir -p "$user_systemd_dir" "$niri_wants_dir" "$hypr_wants_dir" "$mango_wants_dir"
  ensure_user_link "$systemd_dir/sunsetr.service" "$user_systemd_dir/sunsetr.service"
  ensure_user_link "$systemd_dir/sunsetr-scheduler.service" "$user_systemd_dir/sunsetr-scheduler.service"

  # Margo ships its own built-in twilight (blue-light) filter — running
  # sunsetr alongside it races for the same wlr-gamma-control ramp and
  # the screen flickers. The graphical-session.target.wants symlink
  # would auto-start sunsetr under margo too; explicitly delete it
  # (and its scheduler sibling) so margo sessions stay clean.
  rm -f \
    "$user_systemd_dir/sunsetr-auto-profile.service" \
    "$user_systemd_dir/sunsetr-auto-profile.timer" \
    "$user_systemd_dir/graphical-session.target.wants/sunsetr-auto-profile.timer" \
    "$user_systemd_dir/graphical-session.target.wants/sunsetr.service" \
    "$user_systemd_dir/graphical-session.target.wants/sunsetr-scheduler.service" \
    "$user_systemd_dir/niri-sunsetr.service" \
    "$user_systemd_dir/niri-post-daemons.target.wants/niri-sunsetr.service" \
    "$user_systemd_dir/niri-session.target.wants/sunsetr.service" \
    "$user_systemd_dir/niri-session.target.wants/sunsetr-scheduler.service" \
    "$user_systemd_dir/niri-session.target.wants/sunsetr-auto-profile.timer" \
    "$user_systemd_dir/hyprland-session.target.wants/sunsetr.service" \
    "$user_systemd_dir/hyprland-session.target.wants/sunsetr-scheduler.service" \
    "$user_systemd_dir/hyprland-session.target.wants/sunsetr-auto-profile.timer" \
    "$user_systemd_dir/mangowm-session.target.wants/sunsetr.service" \
    "$user_systemd_dir/mangowm-session.target.wants/sunsetr-scheduler.service" \
    "$user_systemd_dir/mangowm-session.target.wants/sunsetr-auto-profile.timer" \
    "$user_systemd_dir/sunsetr.service.d/10-cachy.conf"
  rmdir "$user_systemd_dir/sunsetr.service.d" >/dev/null 2>&1 || true
  # If the graphical-session.target.wants dir is now empty (no other
  # consumers), remove it too — purely cosmetic.
  rmdir "$graphical_wants_dir" >/dev/null 2>&1 || true
  ensure_user_link "$user_systemd_dir/sunsetr.service" "$niri_wants_dir/sunsetr.service"
  ensure_user_link "$user_systemd_dir/sunsetr-scheduler.service" "$niri_wants_dir/sunsetr-scheduler.service"
  ensure_user_link "$user_systemd_dir/sunsetr.service" "$hypr_wants_dir/sunsetr.service"
  ensure_user_link "$user_systemd_dir/sunsetr-scheduler.service" "$hypr_wants_dir/sunsetr-scheduler.service"
  ensure_user_link "$user_systemd_dir/sunsetr.service" "$mango_wants_dir/sunsetr.service"
  ensure_user_link "$user_systemd_dir/sunsetr-scheduler.service" "$mango_wants_dir/sunsetr-scheduler.service"
  run_as_user systemctl --user daemon-reload >/dev/null 2>&1 || true

  if supported_wayland_session_active; then
    run_as_user systemctl --user try-restart sunsetr.service sunsetr-scheduler.service >/dev/null 2>&1 || true
  else
    run_as_user systemctl --user stop sunsetr-scheduler.service sunsetr.service >/dev/null 2>&1 || true
  fi
fi
