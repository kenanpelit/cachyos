#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
source "$REPO_ROOT/modules/base/lib/core.sh"

if ! command -v systemctl >/dev/null 2>&1; then
  exit 0
fi

run_as_user systemctl --user daemon-reload >/dev/null 2>&1 || true
run_as_user systemctl --user enable hyprsunset.service >/dev/null 2>&1 || true
run_as_user systemctl --user try-restart hyprsunset.service >/dev/null 2>&1 || true
