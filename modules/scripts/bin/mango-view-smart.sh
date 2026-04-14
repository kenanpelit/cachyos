#!/usr/bin/env bash
# ==============================================================================
# Script: mango-view-smart.sh
# Description: Workspace back-and-forth for MangoWM (like i3/sway/niri)
# Usage: mango-view-smart.sh <target_tag> [monitor_id]
# ==============================================================================

set -euo pipefail

TARGET_TAG="$1"
MONITOR_ID="${2:-0}"
STATE_DIR="${XDG_RUNTIME_DIR:-/tmp}/mango-view-smart"
mkdir -p "${STATE_DIR}"

# 1. Identify the focused monitor
# mmsg -g output:
# eDP-1 selmon 0
# DP-3 selmon 1
CURRENT_MONITOR="$(mmsg -g 2>/dev/null | awk '$2 == "selmon" && $3 == "1" { print $1; exit }')"
[[ -n "${CURRENT_MONITOR}" ]] || CURRENT_MONITOR="0"

# 2. Get the current tag for this monitor
# mmsg -g output format for tags:
# <monitor> tag <id> <is_visible> <is_selected> <has_urgent>
# We want the tag where <is_selected> (the 4th column) is 1.
CURRENT_TAG="$(mmsg -g 2>/dev/null | grep "^${CURRENT_MONITOR} tag " | awk '$4 == "1" {print $3}' | head -n1)"

# 3. Handle state and toggle
LAST_TAG_FILE="${STATE_DIR}/last-tag-${CURRENT_MONITOR}"
PREV_TAG=""
[[ -f "${LAST_TAG_FILE}" ]] && PREV_TAG="$(cat "${LAST_TAG_FILE}")"

if [[ "${TARGET_TAG}" == "prev" ]]; then
    if [[ -n "${PREV_TAG}" ]]; then
        mmsg -d "view,${PREV_TAG},${MONITOR_ID}"
        echo "${CURRENT_TAG}" > "${LAST_TAG_FILE}"
    fi
    exit 0
fi

if [[ "${CURRENT_TAG}" == "${TARGET_TAG}" ]]; then
    # We are already on the target tag, so toggle back to previous
    if [[ -n "${PREV_TAG}" && "${PREV_TAG}" != "${CURRENT_TAG}" ]]; then
        mmsg -d "view,${PREV_TAG},${MONITOR_ID}"
        echo "${CURRENT_TAG}" > "${LAST_TAG_FILE}"
    fi
else
    # Switch to target tag and save current as previous
    mmsg -d "view,${TARGET_TAG},${MONITOR_ID}"
    echo "${CURRENT_TAG}" > "${LAST_TAG_FILE}"
fi
