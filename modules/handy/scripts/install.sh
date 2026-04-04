#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
MODULE_DIR="$(cd -- "$SCRIPT_DIR/.." && pwd)"
REPO_ROOT="$(cd -- "${MODULE_DIR}/../.." && pwd)"

# shellcheck source=/dev/null
source "${REPO_ROOT}/modules/base/lib/core.sh"

SYSTEMD_DIR="${MODULE_DIR}/dotfiles/systemd/user"
USER_SYSTEMD_DIR="${USER_HOME}/.config/systemd/user"
GRAPHICAL_WANTS_DIR="${USER_SYSTEMD_DIR}/graphical-session.target.wants"
DEFAULT_WANTS_DIR="${USER_SYSTEMD_DIR}/default.target.wants"
BIN_DIR="${USER_HOME}/.local/bin"

ensure_user_link() {
  local src="$1"
  local dst="$2"
  local current=""

  current="$(run_as_user readlink "$dst" 2>/dev/null || true)"
  if [[ "$current" != "$src" ]]; then
    run_as_user ln -sfn "$src" "$dst"
  fi
}

run_as_user mkdir -p "$USER_SYSTEMD_DIR" "$GRAPHICAL_WANTS_DIR" "$DEFAULT_WANTS_DIR" "$BIN_DIR"

ensure_user_link "${SYSTEMD_DIR}/handy.service" "${USER_SYSTEMD_DIR}/handy.service"
ensure_user_link "${MODULE_DIR}/dotfiles/bin/handyctl" "${BIN_DIR}/handyctl"

# Keep Handy tied to the graphical session only.
run_as_user rm -f "${DEFAULT_WANTS_DIR}/handy.service"
ensure_user_link "${USER_SYSTEMD_DIR}/handy.service" "${GRAPHICAL_WANTS_DIR}/handy.service"

if command -v systemctl >/dev/null 2>&1; then
  run_as_user systemctl --user daemon-reload >/dev/null 2>&1 || true

  if run_as_user systemctl --user is-active --quiet graphical-session.target; then
    run_as_user systemctl --user start handy.service >/dev/null 2>&1 || true
  fi
fi
