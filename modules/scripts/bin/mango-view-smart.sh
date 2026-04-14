#!/usr/bin/env bash
set -euo pipefail

TARGET_TAG="$1"
STATE_DIR="${XDG_RUNTIME_DIR:-/tmp}/mango-view-smart"
mkdir -p "${STATE_DIR}"

# 1. Odaklanmış monitörü bul (eDP-1 veya DP-3 gibi)
DATA="$(mmsg -g 2>/dev/null)"
CURRENT_MONITOR="$(echo "$DATA" | awk '$2 == "selmon" && $3 == "1" { print $1; exit }')"
[[ -n "${CURRENT_MONITOR}" ]] || CURRENT_MONITOR="0"

# 2. Mevcut seçili tag'i bul
# format: <monitor> tag <id> <is_visible> <is_selected> <has_urgent>
# selected = column 5
CURRENT_TAG="$(echo "$DATA" | awk -v mon="${CURRENT_MONITOR}" '$1 == mon && $2 == "tag" && $5 == "1" { print $3; exit }')"
[[ -n "${CURRENT_TAG}" ]] || CURRENT_TAG="1"

LAST_TAG_FILE="${STATE_DIR}/last-tag-${CURRENT_MONITOR}"
PREV_TAG=""
[[ -f "${LAST_TAG_FILE}" ]] && PREV_TAG="$(cat "${LAST_TAG_FILE}")"

# 3. Geçiş Mantığı
if [[ "${CURRENT_TAG}" == "${TARGET_TAG}" ]]; then
    # Aynı workspace üzerindeyiz, geri dön (toggle)
    if [[ -n "${PREV_TAG}" && "${PREV_TAG}" != "${CURRENT_TAG}" ]]; then
        mmsg -o "${CURRENT_MONITOR}" -d "view,${PREV_TAG}"
        echo "${CURRENT_TAG}" > "${LAST_TAG_FILE}"
    fi
else
    # Farklı workspace'e geç, mevcut olanı 'sonuncu' olarak kaydet
    mmsg -o "${CURRENT_MONITOR}" -d "view,${TARGET_TAG}"
    echo "${CURRENT_TAG}" > "${LAST_TAG_FILE}"
fi
