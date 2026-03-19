#!/usr/bin/env bash
set -euo pipefail

module_root="$(cd "$(dirname "$0")/.." && pwd)"
bin_dir="$HOME/.local/bin"
systemd_user_dir="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"

mkdir -p "$bin_dir"

for name in stasisctl stasis-lock stasis-kbd-backlight stasis-start; do
  chmod +x "$module_root/scripts/$name" || true
  ln -sf "$module_root/scripts/$name" "$bin_dir/$name"
done

if command -v systemctl >/dev/null 2>&1; then
  systemctl --user daemon-reload >/dev/null 2>&1 || true
  systemctl --user stop stasis.service stasis.timer >/dev/null 2>&1 || true
  systemctl --user disable stasis.service stasis.timer >/dev/null 2>&1 || true
  systemctl --user reset-failed stasis.service >/dev/null 2>&1 || true
  rm -f \
    "$systemd_user_dir/default.target.wants/stasis.timer" \
    "$systemd_user_dir/graphical-session.target.wants/stasis.service" \
    "$systemd_user_dir/hyprland-session.target.wants/stasis.service" \
    "$systemd_user_dir/niri-session.target.wants/stasis.service"
  systemctl --user enable --now stasis.timer >/dev/null 2>&1 || true
fi
