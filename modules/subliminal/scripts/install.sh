#!/usr/bin/env bash
set -euo pipefail

SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENC_FILE="$SRC_DIR/secrets/subliminal.toml"

# Resolve target user/home (works under sudo)
if [[ -n "${SUDO_USER:-}" ]]; then
  TARGET_USER="$SUDO_USER"
  USER_HOME="$(getent passwd "$SUDO_USER" | cut -d: -f6)"
else
  TARGET_USER="$(id -un)"
  USER_HOME="$HOME"
fi

TARGET_DIR="${XDG_CONFIG_HOME:-$USER_HOME/.config}/subliminal"
TARGET_FILE="$TARGET_DIR/subliminal.toml"
KEY_FILE="$USER_HOME/.config/sops/age/keys.txt"
TEMPLATE_FILE="$SRC_DIR/assets/subliminal.template.toml"

if ! command -v sops >/dev/null 2>&1; then
  echo "subliminal: sops not found; skipping decrypt" >&2
  exit 0
fi

mkdir -p "$TARGET_DIR"
if [[ -n "${TARGET_USER:-}" ]]; then
  chown "$TARGET_USER:$TARGET_USER" "$TARGET_DIR" 2>/dev/null || true
fi

if [[ -f "$KEY_FILE" ]]; then
  SOPS_AGE_KEY_FILE="$KEY_FILE" sops -d "$ENC_FILE" > "$TARGET_FILE"
else
  # Fallback: try default sops locations
  sops -d "$ENC_FILE" > "$TARGET_FILE"
fi

chmod 600 "$TARGET_FILE" || true
if [[ -n "${TARGET_USER:-}" ]]; then
  chown "$TARGET_USER:$TARGET_USER" "$TARGET_FILE" 2>/dev/null || true
fi

# Drop a template for reference (non-secret).
if [[ -f "$TEMPLATE_FILE" ]]; then
  cp -f "$TEMPLATE_FILE" "$TARGET_DIR/subliminal.template.toml" 2>/dev/null || true
  chmod 600 "$TARGET_DIR/subliminal.template.toml" 2>/dev/null || true
  if [[ -n "${TARGET_USER:-}" ]]; then
    chown "$TARGET_USER:$TARGET_USER" "$TARGET_DIR/subliminal.template.toml" 2>/dev/null || true
  fi
fi
