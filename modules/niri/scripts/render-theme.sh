#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
MODULE_DIR="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
MANIFEST="${MODULE_DIR}/theme/theme.env"
THEME_OUT="${MODULE_DIR}/dotfiles/niri/generated/theme.kdl"

usage() {
  cat <<'EOF'
Usage: render-theme.sh [--check]

Without arguments, regenerates the derived Niri theme file.
With --check, verifies that generated/theme.kdl matches theme/theme.env.
EOF
}

mode="write"
case "${1:-}" in
  ""|--write)
    ;;
  --check)
    mode="check"
    ;;
  -h|--help)
    usage
    exit 0
    ;;
  *)
    usage >&2
    exit 2
    ;;
esac

# shellcheck source=/dev/null
source "${MANIFEST}"

manifest_checksum="$(sha256sum "${MANIFEST}" | awk '{print $1}')"
tmp_theme="$(mktemp)"

cleanup() {
  rm -f "${tmp_theme}"
}
trap cleanup EXIT

: "${NIRI_CURSOR_THEME:=capitaine-cursors}"
: "${NIRI_CURSOR_SIZE:=24}"
: "${NIRI_OVERVIEW_BACKDROP_HEX:=313244}"
: "${NIRI_OVERVIEW_SHADOW_HEX:=00000050}"
: "${NIRI_OVERVIEW_SHADOW_SOFTNESS:=40}"
: "${NIRI_OVERVIEW_SHADOW_SPREAD:=12}"
: "${NIRI_OVERVIEW_SHADOW_OFFSET_X:=0}"
: "${NIRI_OVERVIEW_SHADOW_OFFSET_Y:=12}"
: "${NIRI_LAYOUT_BACKGROUND_HEX:=00000000}"
: "${NIRI_FOCUS_RING_WIDTH:=3}"
: "${NIRI_FOCUS_RING_ACTIVE_FROM_HEX:=bd8ff5}"
: "${NIRI_FOCUS_RING_ACTIVE_TO_HEX:=cba6f7}"
: "${NIRI_FOCUS_RING_INACTIVE_HEX:=313244}"
: "${NIRI_FOCUS_RING_URGENT_HEX:=f38ba8}"
: "${NIRI_LAYOUT_SHADOW_HEX:=11111b70}"
: "${NIRI_TAB_WIDTH:=4}"
: "${NIRI_TAB_GAP:=6}"
: "${NIRI_TAB_LENGTH:=0.9}"
: "${NIRI_TAB_GAPS_BETWEEN:=4}"
: "${NIRI_TAB_CORNER_RADIUS:=8}"
: "${NIRI_TAB_ACTIVE_HEX:=cba6f7}"
: "${NIRI_TAB_INACTIVE_HEX:=6b02e9}"
: "${NIRI_TAB_URGENT_HEX:=f38ba8}"
: "${NIRI_INSERT_HINT_HEX:=cba6f780}"
: "${NIRI_MRU_ACTIVE_HEX:=cba6f7}"
: "${NIRI_MRU_URGENT_HEX:=f38ba8}"
: "${NIRI_MRU_PADDING:=18}"
: "${NIRI_MRU_CORNER_RADIUS:=14}"
: "${NIRI_MRU_MAX_HEIGHT:=560}"
: "${NIRI_MRU_MAX_SCALE:=0.60}"
: "${NIRI_WINDOW_CORNER_RADIUS:=12}"
: "${NIRI_TILING_SHADOW_HEX:=00000060}"
: "${NIRI_TILING_SHADOW_OFFSET_X:=0}"
: "${NIRI_TILING_SHADOW_OFFSET_Y:=4}"
: "${NIRI_TILING_SHADOW_SPREAD:=0}"
: "${NIRI_TILING_SHADOW_SOFTNESS:=16}"
: "${NIRI_LAYER_POPUP_SHADOW_HEX:=00000060}"
: "${NIRI_LAYER_POPUP_SHADOW_SPREAD:=2}"
: "${NIRI_LAYER_POPUP_SHADOW_SOFTNESS:=12}"
: "${NIRI_NOTIFICATIONS_CORNER_RADIUS:=12}"
: "${NIRI_CAST_TARGET_ACTIVE_HEX:=f38ba8}"
: "${NIRI_CAST_TARGET_INACTIVE_HEX:=7d0d2d}"

cat >"${tmp_theme}" <<EOF
// Generated from modules/niri/theme/theme.env.
// Update the manifest and rerun modules/niri/scripts/render-theme.sh.
// Source checksum: ${manifest_checksum}

cursor {
  xcursor-theme "${NIRI_CURSOR_THEME}"
  xcursor-size ${NIRI_CURSOR_SIZE}
}

overview {
  backdrop-color "#${NIRI_OVERVIEW_BACKDROP_HEX}"
  workspace-shadow {
    softness ${NIRI_OVERVIEW_SHADOW_SOFTNESS}
    spread ${NIRI_OVERVIEW_SHADOW_SPREAD}
    offset x=${NIRI_OVERVIEW_SHADOW_OFFSET_X} y=${NIRI_OVERVIEW_SHADOW_OFFSET_Y}
    color "#${NIRI_OVERVIEW_SHADOW_HEX}"
  }
}

layout {
  background-color "#${NIRI_LAYOUT_BACKGROUND_HEX}"

  focus-ring {
    on
    width ${NIRI_FOCUS_RING_WIDTH}
    active-gradient from="#${NIRI_FOCUS_RING_ACTIVE_FROM_HEX}" to="#${NIRI_FOCUS_RING_ACTIVE_TO_HEX}" angle=45 relative-to="workspace-view" in="oklch shorter hue"
    inactive-color "#${NIRI_FOCUS_RING_INACTIVE_HEX}"
    urgent-color "#${NIRI_FOCUS_RING_URGENT_HEX}"
  }

  shadow {
    color "#${NIRI_LAYOUT_SHADOW_HEX}"
  }

  tab-indicator {
    hide-when-single-tab
    place-within-column
    width ${NIRI_TAB_WIDTH}
    gap ${NIRI_TAB_GAP}
    length total-proportion=${NIRI_TAB_LENGTH}
    position "top"
    gaps-between-tabs ${NIRI_TAB_GAPS_BETWEEN}
    corner-radius ${NIRI_TAB_CORNER_RADIUS}
    active-color "#${NIRI_TAB_ACTIVE_HEX}"
    inactive-color "#${NIRI_TAB_INACTIVE_HEX}"
    urgent-color "#${NIRI_TAB_URGENT_HEX}"
  }

  insert-hint {
    color "#${NIRI_INSERT_HINT_HEX}"
  }
}

recent-windows {
  highlight {
    active-color "#${NIRI_MRU_ACTIVE_HEX}"
    urgent-color "#${NIRI_MRU_URGENT_HEX}"
    padding ${NIRI_MRU_PADDING}
    corner-radius ${NIRI_MRU_CORNER_RADIUS}
  }

  previews {
    max-height ${NIRI_MRU_MAX_HEIGHT}
    max-scale ${NIRI_MRU_MAX_SCALE}
  }
}

window-rule {
  geometry-corner-radius ${NIRI_WINDOW_CORNER_RADIUS}
  clip-to-geometry true
}

window-rule {
  match is-floating=true
  shadow {
    on
  }
}

window-rule {
  match is-floating=false
  shadow {
    on
    color "#${NIRI_TILING_SHADOW_HEX}"
    offset x=${NIRI_TILING_SHADOW_OFFSET_X} y=${NIRI_TILING_SHADOW_OFFSET_Y}
    spread ${NIRI_TILING_SHADOW_SPREAD}
    softness ${NIRI_TILING_SHADOW_SOFTNESS}
  }
}

window-rule {
  match is-window-cast-target=true
  focus-ring {
    active-color "#${NIRI_CAST_TARGET_ACTIVE_HEX}"
    inactive-color "#${NIRI_CAST_TARGET_INACTIVE_HEX}"
  }
  opacity 1.0
}

layer-rule {
  match namespace=r#"(^|.*[:\-])(launcher|osd|popup).*$"#
  shadow {
    on
    color "#${NIRI_LAYER_POPUP_SHADOW_HEX}"
    spread ${NIRI_LAYER_POPUP_SHADOW_SPREAD}
    softness ${NIRI_LAYER_POPUP_SHADOW_SOFTNESS}
  }
}

layer-rule {
  match namespace="^notifications$"
  geometry-corner-radius ${NIRI_NOTIFICATIONS_CORNER_RADIUS}
}
EOF

if [[ "${mode}" == "check" ]]; then
  diff -u "${THEME_OUT}" "${tmp_theme}"
  exit 0
fi

install -D -m 644 "${tmp_theme}" "${THEME_OUT}"
