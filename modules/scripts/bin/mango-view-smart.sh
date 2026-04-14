#!/usr/bin/env bash
# ==============================================================================
# mango-view-smart
# ==============================================================================

set -euo pipefail

TARGET_TAG="$1"
MONITOR_ID="${2:-0}"
STATE_DIR="${XDG_RUNTIME_DIR:-/tmp}/mango-view-smart"
mkdir -p "${STATE_DIR}"

# Debug için mmsg yolunu bul
MMSG="$(command -v mmsg || echo "/usr/bin/mmsg")"

# 1. Odaklanmış monitörü bul
CURRENT_MONITOR="$($MMSG -g 2>/dev/null | awk '$2 == "selmon" && $3 == "1" { print $1; exit }')"
[[ -n "${CURRENT_MONITOR}" ]] || CURRENT_MONITOR="0"

# 2. Mevcut tag'i bul (Seçili olan tag'in 4. veya 5. sütununda '1' olur)
# mmsg -g | grep "^DP-3 tag " çıktısını tarar
CURRENT_TAG="$($MMSG -g 2>/dev/null | grep "^${CURRENT_MONITOR} tag " | awk '$4 == "1" || $5 == "1" {print $3; exit}')"
[[ -n "${CURRENT_TAG}" ]] || CURRENT_TAG="1"

LAST_TAG_FILE="${STATE_DIR}/last-tag-${CURRENT_MONITOR}"
PREV_TAG=""
[[ -f "${LAST_TAG_FILE}" ]] && PREV_TAG="$(cat "${LAST_TAG_FILE}")"

# 3. Geçiş Mantığı
if [[ "${CURRENT_TAG}" == "${TARGET_TAG}" ]]; then
    if [[ -n "${PREV_TAG}" && "${PREV_TAG}" != "${CURRENT_TAG}" ]]; then
        $MMSG -d "view,${PREV_TAG},${MONITOR_ID}"
        echo "${CURRENT_TAG}" > "${LAST_TAG_FILE}"
    fi
else
    $MMSG -d "view,${TARGET_TAG},${MONITOR_ID}"
    echo "${CURRENT_TAG}" > "${LAST_TAG_FILE}"
fi
