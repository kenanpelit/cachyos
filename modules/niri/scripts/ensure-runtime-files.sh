#!/usr/bin/env bash
set -euo pipefail

DMS_DIR="$HOME/.config/niri/dms"
mkdir -p "$DMS_DIR"

for f in outputs.kdl zen.kdl cursor.kdl alttab.kdl layout.kdl; do
  path="$DMS_DIR/$f"
  # If it's a broken symlink or doesn't exist, create it
  if [ ! -e "$path" ]; then
    echo "Creating empty runtime file: $path"
    : > "$path"
  fi
  chmod 0644 "$path" || true
done