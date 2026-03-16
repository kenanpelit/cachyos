#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
MODULE_DIR="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
AUTOSTART_DIR="${HOME}/.config/autostart"

mkdir -p "${AUTOSTART_DIR}"

for name in nm-applet.desktop blueman.desktop gnome-keyring-secrets.desktop; do
  ln -snf "${MODULE_DIR}/dotfiles/autostart/${name}" "${AUTOSTART_DIR}/${name}"
done
