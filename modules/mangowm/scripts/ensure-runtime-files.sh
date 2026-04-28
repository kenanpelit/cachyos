#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
MODULE_DIR="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
REPO_ROOT="$(cd -- "${MODULE_DIR}/../.." && pwd)"
source "${REPO_ROOT}/modules/base/lib/core.sh"

MANGO_DIR="${USER_HOME}/.config/mango"
RUNTIME_DIR="${MANGO_DIR}/runtime"
GENERATED_SOURCE_DIR="${MODULE_DIR}/dotfiles/mango/generated"

if [ "$(id -u)" -eq 0 ]; then
	install -d -m0755 -o "${REAL_USER}" "${MANGO_DIR}" "${RUNTIME_DIR}"
else
	mkdir -p "${MANGO_DIR}" "${RUNTIME_DIR}"
fi

run_module_script() {
	if [ "$(id -u)" -eq 0 ]; then
		run_as_user "$@"
	else
		"$@"
	fi
}

link_runtime_asset() {
	local name="$1"
	local source_path="${GENERATED_SOURCE_DIR}/${name}"
	local target_path="${RUNTIME_DIR}/${name}"

	run_as_user rm -f "${target_path}" 2>/dev/null || true
	run_as_user ln -sfnT "${source_path}" "${target_path}"
}

run_module_script "${MODULE_DIR}/scripts/render-packages.sh"
run_module_script "${MODULE_DIR}/scripts/render-theme.sh"
run_module_script "${MODULE_DIR}/scripts/render-profile.sh"
run_module_script "${MODULE_DIR}/scripts/render-workspace-assets.sh"
run_module_script "${MODULE_DIR}/scripts/render-window-rules.sh"
run_module_script "${MODULE_DIR}/scripts/render-keybind-cheatsheet.sh"

for runtime_asset in \
	profile.conf \
	workspace-binds.conf \
	workspace-rules.conf \
	window-rules.conf \
	keybind-cheatsheet.conf; do
	link_runtime_asset "${runtime_asset}"
done

if command -v systemctl >/dev/null 2>&1; then
	run_as_user systemctl --user daemon-reload >/dev/null 2>&1 || true
fi
