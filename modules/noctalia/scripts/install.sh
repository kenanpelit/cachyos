#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
source "$REPO_ROOT/modules/base/lib/core.sh"

if command -v systemctl >/dev/null 2>&1; then
  run_as_user systemctl --user daemon-reload >/dev/null 2>&1 || true
fi

# Reduce firewall poll noise from the NUFW plugin.
settings_file="$USER_HOME/.config/noctalia/settings.json"
if command -v jq >/dev/null 2>&1 && [[ -f "$settings_file" ]]; then
  tmp_file="$(mktemp "${TMPDIR:-/tmp}/noctalia-settings.XXXXXX.json")"
  if jq '
    (.bar.pluginPanels[]? | select(.id == "plugin:6ee06e:nufw").defaultSettings.watchdogInterval) |=
      (if . == null or . < 30000 then 60000 else . end)
  ' "$settings_file" >"$tmp_file"; then
    run_as_user install -m 0644 "$tmp_file" "$settings_file" >/dev/null 2>&1 || true
  fi
  rm -f "$tmp_file"
fi
