#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
MODULE_DIR="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
REPO_ROOT="$(cd -- "${MODULE_DIR}/../.." && pwd)"
source "${REPO_ROOT}/modules/base/lib/core.sh"

# `.config/margo` + the `layouts/` subdir (mlayout layout snapshots live
# there now; the dotfiles symlink for layout_vertical-ext-top.conf targets
# ~/.config/margo/layouts/, so its parent must exist before linking).
if [ "$(id -u)" -eq 0 ]; then
	install -d -m0755 -o "${REAL_USER}" "${USER_HOME}/.config/margo" "${USER_HOME}/.config/margo/layouts"
else
	mkdir -p "${USER_HOME}/.config/margo/layouts"
fi

if command -v systemctl >/dev/null 2>&1; then
	run_as_user systemctl --user daemon-reload >/dev/null 2>&1 || true
fi
