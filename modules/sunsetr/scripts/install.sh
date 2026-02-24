#!/usr/bin/env bash
set -euo pipefail

module_root="$(cd "$(dirname "$0")/.." && pwd)"
repo_root="$(cd "$module_root/.." && pwd)"
real_user="${SUDO_USER:-$(id -un)}"
user_home="$(getent passwd "$real_user" | cut -d: -f6 2>/dev/null || true)"

if [[ -z "${user_home:-}" ]]; then
  user_home="$(eval echo "~$real_user")"
fi

bin_dir="$user_home/.local/bin"
script_src="$repo_root/scripts/bin/sunsetr-set.sh"

if [[ ! -f "$script_src" ]]; then
  echo "[sunsetr-install] WARN: source script not found: $script_src" >&2
  exit 0
fi

mkdir -p "$bin_dir"
ln -sf "$script_src" "$bin_dir/sunsetr-set"

if [[ "$(id -u)" -eq 0 ]]; then
  user_group="$(id -gn "$real_user" 2>/dev/null || true)"
  chown "$real_user:${user_group:-$real_user}" "$bin_dir" || true
  chmod 755 "$bin_dir" || true
  chown -h "$real_user:${user_group:-$real_user}" "$bin_dir/sunsetr-set" || true
fi

run_as_user() {
  if [[ "$real_user" != "$(id -un)" ]]; then
    local user_id
    user_id="$(id -u "$real_user")"
    sudo -E -u "$real_user" \
      XDG_RUNTIME_DIR="/run/user/$user_id" \
      DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$user_id/bus" \
      "$@"
  else
    "$@"
  fi
}

if command -v systemctl >/dev/null 2>&1; then
  run_as_user systemctl --user daemon-reload >/dev/null 2>&1 || true

  # Keep sunsetr manual-only: do not auto-start at login.
  run_as_user systemctl --user disable --now sunsetr.service >/dev/null 2>&1 || true
fi
