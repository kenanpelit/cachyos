#!/usr/bin/env bash
# ==============================================================================
# Script: niri-status-notifier-ready.sh
# Description: Wait for StatusNotifierWatcher before Niri tray applets start.
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HELPER="${SCRIPT_DIR}/status-notifier-ready.sh"
[[ -r "${HELPER}" ]] || HELPER="${SCRIPT_DIR}/status-notifier-ready"

export STATUS_NOTIFIER_READY_LOG_TAG="${STATUS_NOTIFIER_READY_LOG_TAG:-niri-status-notifier-ready}"

exec "${HELPER}" "$@"
