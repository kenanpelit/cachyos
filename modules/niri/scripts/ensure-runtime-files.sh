#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
repo_root="$(cd "$script_dir/../../.." && pwd)"
source "$repo_root/modules/base/lib/core.sh"

NIRI_DIR="$USER_HOME/.config/niri"
DMS_DIR="$NIRI_DIR/dms"
USER_GROUP=""
if [ "$(id -u)" -eq 0 ]; then
  USER_GROUP="$(id -gn "$REAL_USER" 2>/dev/null || true)"
fi

if [ "$(id -u)" -eq 0 ] && [ -n "$USER_GROUP" ]; then
  install -d -m0755 -o "$REAL_USER" -g "$USER_GROUP" "$NIRI_DIR" "$DMS_DIR"
  chown "$REAL_USER:$USER_GROUP" "$NIRI_DIR" "$DMS_DIR" 2>/dev/null || true
else
  mkdir -p "$DMS_DIR"
fi

for f in outputs.kdl monitor-auto.kdl zen.kdl cursor.kdl alttab.kdl layout.kdl windowrules.kdl; do
  path="$DMS_DIR/$f"
  # If it's a broken symlink or doesn't exist, create it
  if [ ! -e "$path" ]; then
    echo "Creating empty runtime file: $path"
    if [ "$(id -u)" -eq 0 ] && [ -n "$USER_GROUP" ]; then
      install -m0644 -o "$REAL_USER" -g "$USER_GROUP" /dev/null "$path"
    else
      : > "$path"
    fi
  fi
  chmod 0644 "$path" || true
done

# Run health check validation
if [[ -x "$script_dir/validate.sh" ]]; then
  "$script_dir/validate.sh"
fi

if command -v systemctl >/dev/null 2>&1; then
  systemctl --user daemon-reload >/dev/null 2>&1 || true
fi
