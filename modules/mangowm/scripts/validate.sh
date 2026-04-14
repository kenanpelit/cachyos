#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
MODULE_DIR="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
REPO_ROOT="$(cd -- "${MODULE_DIR}/../.." && pwd)"
CONFIG_FILE="${MODULE_DIR}/dotfiles/mango/config.conf"

command -v bash >/dev/null 2>&1 || { echo "bash is required" >&2; exit 1; }
command -v mango >/dev/null 2>&1 || { echo "mango is required" >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "jq is required" >&2; exit 1; }

"${MODULE_DIR}/scripts/render-theme.sh" --check
"${MODULE_DIR}/scripts/render-profile.sh" --check
"${MODULE_DIR}/scripts/render-workspace-assets.sh" --check
jq empty "${REPO_ROOT}/modules/niri/workspaces/workspaces.json"

scripts=(
  "${MODULE_DIR}/scripts/install.sh"
  "${MODULE_DIR}/scripts/render-theme.sh"
  "${MODULE_DIR}/scripts/render-profile.sh"
  "${MODULE_DIR}/scripts/render-workspace-assets.sh"
  "${MODULE_DIR}/scripts/validate.sh"
  "${REPO_ROOT}/modules/scripts/bin/mango-monitor-smart.sh"
  "${REPO_ROOT}/modules/scripts/bin/mango-workspace-smart.sh"
  "${REPO_ROOT}/modules/scripts/bin/mango-session-common.sh"
  "${REPO_ROOT}/modules/scripts/bin/mango-session-refresh.sh"
  "${REPO_ROOT}/modules/scripts/bin/mango-session-doctor.sh"
  "${REPO_ROOT}/modules/scripts/bin/mango-session-init.sh"
  "${REPO_ROOT}/modules/scripts/bin/mango-bootstrap.sh"
  "${REPO_ROOT}/modules/scripts/bin/mango-post-bootstrap.sh"
  "${REPO_ROOT}/modules/scripts/bin/mango-desktop-settings.sh"
  "${REPO_ROOT}/modules/scripts/bin/mango-status-notifier-ready.sh"
  "${REPO_ROOT}/modules/sessions/dotfiles/mango-session"
  "${REPO_ROOT}/modules/sessions/dotfiles/mango-uwsm-session"
)

for script in "${scripts[@]}"; do
  bash -n "${script}"
done

mango -c "${CONFIG_FILE}" -p
