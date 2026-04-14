#!/usr/bin/env bash
set -euo pipefail

TARGET_TAG="$1"
MONITOR_ID="${2:-0}"
STATE_DIR="${XDG_RUNTIME_DIR:-/tmp}/mango-view-smart"
mkdir -p "${STATE_DIR}"

# Parse mmsg -g to find focused monitor and its selected tag
# format: <monitor> tag <id> <is_visible> <is_selected> <has_urgent>
# or: <monitor> selmon <0|1>

DATA="$(mmsg -g 2>/dev/null)"

CURRENT_MONITOR="$(echo "$DATA" | awk '$2 == "selmon" && $3 == "1" { print $1; exit }')"
[[ -n "${CURRENT_MONITOR}" ]] || CURRENT_MONITOR="$(echo "$DATA" | awk '$2 == "selmon" { print $1; exit }')"

CURRENT_TAG="$(echo "$DATA" | awk -v mon="${CURRENT_MONITOR}" '$1 == mon && $2 == "tag" && $5 == "1" { print $3; exit }')"

# fallback if CURRENT_TAG is empty
[[ -n "${CURRENT_TAG}" ]] || CURRENT_TAG="1"

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
    if [[ -n "${PREV_TAG}" && "${PREV_TAG}" != "${CURRENT_TAG}" ]]; then
        mmsg -d "view,${PREV_TAG},${MONITOR_ID}"
        echo "${CURRENT_TAG}" > "${LAST_TAG_FILE}"
    fi
else
    mmsg -d "view,${TARGET_TAG},${MONITOR_ID}"
    echo "${CURRENT_TAG}" > "${LAST_TAG_FILE}"
fi
