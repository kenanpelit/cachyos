#!/usr/bin/env bash
set -euo pipefail

# Use absolute path for mmsg to be safe in compositor environment
MMSG="/usr/bin/mmsg"
[[ -x "$MMSG" ]] || MMSG="mmsg"

TARGET_TAG="$1"
MONITOR_ID="${2:-0}"
STATE_DIR="${XDG_RUNTIME_DIR:-/tmp}/mango-view-smart"
mkdir -p "${STATE_DIR}"

DATA="$($MMSG -g 2>/dev/null)"

CURRENT_MONITOR="$(echo "$DATA" | awk '$2 == "selmon" && $3 == "1" { print $1; exit }')"
[[ -n "${CURRENT_MONITOR}" ]] || CURRENT_MONITOR="$(echo "$DATA" | awk '$2 == "selmon" { print $1; exit }')"

# format: <monitor> tag <id> <is_visible> <is_selected> <has_urgent>
# selected is column 5
CURRENT_TAG="$(echo "$DATA" | awk -v mon="${CURRENT_MONITOR}" '$1 == mon && $2 == "tag" && $5 == "1" { print $3; exit }')"
[[ -n "${CURRENT_TAG}" ]] || CURRENT_TAG="1"

LAST_TAG_FILE="${STATE_DIR}/last-tag-${CURRENT_MONITOR}"
PREV_TAG=""
[[ -f "${LAST_TAG_FILE}" ]] && PREV_TAG="$(cat "${LAST_TAG_FILE}")"

if [[ "${TARGET_TAG}" == "prev" ]]; then
    if [[ -n "${PREV_TAG}" ]]; then
        $MMSG -d "view,${PREV_TAG},${MONITOR_ID}"
        echo "${CURRENT_TAG}" > "${LAST_TAG_FILE}"
    fi
    exit 0
fi

if [[ "${CURRENT_TAG}" == "${TARGET_TAG}" ]]; then
    if [[ -n "${PREV_TAG}" && "${PREV_TAG}" != "${CURRENT_TAG}" ]]; then
        $MMSG -d "view,${PREV_TAG},${MONITOR_ID}"
        echo "${CURRENT_TAG}" > "${LAST_TAG_FILE}"
    fi
else
    $MMSG -d "view,${TARGET_TAG},${MONITOR_ID}"
    echo "${CURRENT_TAG}" > "${LAST_TAG_FILE}"
fi
