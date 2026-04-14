#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
MODULE_DIR="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
REPO_ROOT="$(cd -- "${MODULE_DIR}/../.." && pwd)"

# shellcheck source=/dev/null
source "${REPO_ROOT}/modules/base/lib/core.sh"

run_module_script() {
  if [ "$(id -u)" -eq 0 ]; then
    run_as_user "$@"
  else
    "$@"
  fi
}

run_module_script "${MODULE_DIR}/scripts/render-theme.sh"
run_module_script "${MODULE_DIR}/scripts/render-profile.sh"
run_module_script "${MODULE_DIR}/scripts/render-workspace-assets.sh"
run_module_script "${MODULE_DIR}/scripts/validate.sh"

if command -v systemctl >/dev/null 2>&1; then
  run_as_user systemctl --user daemon-reload >/dev/null 2>&1 || true
fi
