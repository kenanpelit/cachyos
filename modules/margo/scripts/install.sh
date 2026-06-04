#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
MODULE_DIR="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
REPO_ROOT="$(cd -- "${MODULE_DIR}/../.." && pwd)"
source "${REPO_ROOT}/modules/base/lib/core.sh"

# `.config/margo` + its subdirs: `layouts/` (mlayout layout snapshots) and
# `conf.d/` (margo config fragments — colors.conf / taglayouts.conf /
# mlayout.conf, written by matugen / mshell / mlayout and `source`d from
# config.conf). Pre-create them so the first source/symlink never races a
# missing parent.
if [ "$(id -u)" -eq 0 ]; then
	install -d -m0755 -o "${REAL_USER}" \
		"${USER_HOME}/.config/margo" \
		"${USER_HOME}/.config/margo/layouts" \
		"${USER_HOME}/.config/margo/conf.d" \
		"${USER_HOME}/.config/margo/twilight/presets" \
		"${USER_HOME}/.config/margo/mshell/profiles"
else
	mkdir -p \
		"${USER_HOME}/.config/margo/layouts" \
		"${USER_HOME}/.config/margo/conf.d" \
		"${USER_HOME}/.config/margo/twilight/presets" \
		"${USER_HOME}/.config/margo/mshell/profiles"
fi

if command -v systemctl >/dev/null 2>&1; then
	run_as_user systemctl --user daemon-reload >/dev/null 2>&1 || true
fi
