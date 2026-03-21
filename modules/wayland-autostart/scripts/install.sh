#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
MODULE_DIR="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
REPO_ROOT="$(cd -- "${MODULE_DIR}/../.." && pwd)"

# shellcheck source=/dev/null
source "${REPO_ROOT}/modules/base/lib/core.sh"

AUTOSTART_DIR="${USER_HOME}/.config/autostart"

run_as_user mkdir -p "${AUTOSTART_DIR}"

for name in nm-applet.desktop blueman.desktop gnome-keyring-secrets.desktop; do
  run_as_user ln -sfn "${MODULE_DIR}/dotfiles/autostart/${name}" "${AUTOSTART_DIR}/${name}"
done
