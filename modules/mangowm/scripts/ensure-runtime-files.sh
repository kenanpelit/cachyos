#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
MODULE_DIR="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
REPO_ROOT="$(cd -- "${MODULE_DIR}/../.." && pwd)"
source "${REPO_ROOT}/modules/base/lib/core.sh"

MANGO_DIR="${USER_HOME}/.config/mango"
RUNTIME_DIR="${MANGO_DIR}/runtime"

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

run_module_script "${MODULE_DIR}/scripts/render-theme.sh"
run_module_script "${MODULE_DIR}/scripts/render-profile.sh" --out-dir "${RUNTIME_DIR}"
run_module_script "${MODULE_DIR}/scripts/render-workspace-assets.sh" --runtime-dir "${RUNTIME_DIR}"
run_module_script "${MODULE_DIR}/scripts/render-keybind-cheatsheet.sh" --runtime-dir "${RUNTIME_DIR}"
run_module_script "${MODULE_DIR}/scripts/validate.sh"

if command -v systemctl >/dev/null 2>&1; then
  run_as_user systemctl --user daemon-reload >/dev/null 2>&1 || true
fi
