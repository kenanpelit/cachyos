#!/usr/bin/env bash
set -euo pipefail

module_root="$(cd "$(dirname "$0")/.." && pwd)"
bin_dir="$HOME/.local/bin"

mkdir -p "$bin_dir"

for name in dms-plugin-sync dms-resume-restart; do
  chmod +x "$module_root/scripts/$name" || true
  ln -sf "$module_root/scripts/$name" "$bin_dir/$name"
done

# Best-effort: fix lock setting if settings.json exists
settings="$HOME/.config/DankMaterialShell/settings.json"
if command -v jq >/dev/null 2>&1 && [ -f "$settings" ]; then
  current="$(jq -r '.loginctlLockIntegration // empty' "$settings" 2>/dev/null || true)"
  if [ "$current" != "true" ]; then
    tmp="$(mktemp)"
    jq '.loginctlLockIntegration = true' "$settings" >"$tmp" && mv "$tmp" "$settings"
  fi
fi

# Best-effort: enable services for both session targets if systemd is available
if command -v systemctl >/dev/null 2>&1; then
  systemctl --user daemon-reload >/dev/null 2>&1 || true

  # Enable into session targets so `niri-set env` / hyprland exec-once starts them.
  systemctl --user enable dms.service dms-plugin-sync.service dms-resume-restart.service >/dev/null 2>&1 || true
fi
