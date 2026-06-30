#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
MODULE_DIR="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
REPO_ROOT="$(cd -- "${MODULE_DIR}/../.." && pwd)"

# shellcheck source=/dev/null
source "${REPO_ROOT}/modules/base/lib/core.sh"

SUDO=""
if [[ "$(id -u)" -ne 0 ]]; then
  if ! command -v sudo >/dev/null 2>&1; then
    echo "sudo is required" >&2
    exit 1
  fi
  SUDO="sudo"
fi

LIMITS_SRC="${MODULE_DIR}/dotfiles/limits.d/30-pipewire-rt.conf"
LIMITS_DST_DIR="/etc/security/limits.d"
LIMITS_DST="${LIMITS_DST_DIR}/30-pipewire-rt.conf"

${SUDO} mkdir -p "${LIMITS_DST_DIR}"
${SUDO} install -m 644 "${LIMITS_SRC}" "${LIMITS_DST}"

if command -v systemctl >/dev/null 2>&1; then
  # Reload unit files so the drop-ins are picked up, but do NOT restart the
  # audio services here. This hook runs on every `mdots sync` (post_hook_behavior:
  # always), and restarting pipewire mid-session severs wayle-audio's libpulse
  # connection (it has no reconnect) — killing volume keys + the OSD until the
  # shell is restarted. The RT/nice limits.d only apply to a new login anyway,
  # and the systemd drop-ins take effect the next time pipewire starts, so the
  # config lands on the next relogin/reboot with no audio interruption.
  run_as_user systemctl --user daemon-reload >/dev/null 2>&1 || true
fi
