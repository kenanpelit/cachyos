#!/usr/bin/env bash
set -euo pipefail

SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENC_FILE="$SRC_DIR/secrets/subliminal.toml"

TARGET_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/subliminal"
TARGET_FILE="$TARGET_DIR/subliminal.toml"

if ! command -v sops >/dev/null 2>&1; then
  echo "subliminal: sops not found; skipping decrypt" >&2
  exit 0
fi

mkdir -p "$TARGET_DIR"

sops -d "$ENC_FILE" > "$TARGET_FILE"
chmod 600 "$TARGET_FILE" || true
