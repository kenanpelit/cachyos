#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
MODULE_DIR="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
MANIFEST="${MODULE_DIR}/theme/theme.env"
THEME_OUT="${MODULE_DIR}/dotfiles/mango/generated/theme.conf"

usage() {
  cat <<'EOF'
Usage: render-theme.sh [--check]

Without arguments, regenerates the derived MangoWM theme file.
With --check, verifies that generated/theme.conf matches theme/theme.env.
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
package_variant="${MANGO_PACKAGE_VARIANT:-wlonly}"

cleanup() {
  rm -f "${tmp_theme}"
}
trap cleanup EXIT

cat >"${tmp_theme}" <<EOF
# Generated from modules/mangowm/theme/theme.env.
# Update the manifest and rerun modules/mangowm/scripts/render-theme.sh.
# Source checksum: ${manifest_checksum}
# Package variant: ${package_variant}

EOF

if [[ "${package_variant}" != "wlonly" ]]; then
cat >>"${tmp_theme}" <<EOF
blur=${MANGO_BLUR}
blur_layer=${MANGO_BLUR_LAYER}
blur_optimized=${MANGO_BLUR_OPTIMIZED}
blur_params_num_passes=${MANGO_BLUR_PASSES}
blur_params_radius=${MANGO_BLUR_RADIUS}
blur_params_noise=${MANGO_BLUR_NOISE}
blur_params_brightness=${MANGO_BLUR_BRIGHTNESS}
blur_params_contrast=${MANGO_BLUR_CONTRAST}
blur_params_saturation=${MANGO_BLUR_SATURATION}

shadows=${MANGO_SHADOWS}
layer_shadows=${MANGO_LAYER_SHADOWS}
shadow_only_floating=${MANGO_SHADOW_ONLY_FLOATING}
shadows_size=${MANGO_SHADOWS_SIZE}
shadows_blur=${MANGO_SHADOWS_BLUR}
shadows_position_x=${MANGO_SHADOWS_POSITION_X}
shadows_position_y=${MANGO_SHADOWS_POSITION_Y}
shadowscolor=${MANGO_SHADOW_COLOR}

border_radius=${MANGO_BORDER_RADIUS}
no_radius_when_single=${MANGO_NO_RADIUS_WHEN_SINGLE}
EOF
else
cat >>"${tmp_theme}" <<'EOF'
# wlonly build: scenefx-dependent effects are intentionally omitted.
# Unsupported here: blur, shadows, border radius.
EOF
fi

cat >>"${tmp_theme}" <<EOF

focused_opacity=${MANGO_FOCUSED_OPACITY}
unfocused_opacity=${MANGO_UNFOCUSED_OPACITY}

animations=${MANGO_ANIMATIONS}
layer_animations=${MANGO_LAYER_ANIMATIONS}
animation_type_open=${MANGO_ANIMATION_TYPE_OPEN}
animation_type_close=${MANGO_ANIMATION_TYPE_CLOSE}
animation_fade_in=${MANGO_ANIMATION_FADE_IN}
animation_fade_out=${MANGO_ANIMATION_FADE_OUT}
tag_animation_direction=${MANGO_TAG_ANIMATION_DIRECTION}
zoom_initial_ratio=${MANGO_ZOOM_INITIAL_RATIO}
zoom_end_ratio=${MANGO_ZOOM_END_RATIO}
fadein_begin_opacity=${MANGO_FADEIN_BEGIN_OPACITY}
fadeout_begin_opacity=${MANGO_FADEOUT_BEGIN_OPACITY}
animation_duration_move=${MANGO_ANIMATION_DURATION_MOVE}
animation_duration_open=${MANGO_ANIMATION_DURATION_OPEN}
animation_duration_tag=${MANGO_ANIMATION_DURATION_TAG}
animation_duration_close=${MANGO_ANIMATION_DURATION_CLOSE}
animation_duration_focus=${MANGO_ANIMATION_DURATION_FOCUS}
animation_curve_open=${MANGO_ANIMATION_CURVE_OPEN}
animation_curve_move=${MANGO_ANIMATION_CURVE_MOVE}
animation_curve_tag=${MANGO_ANIMATION_CURVE_TAG}
animation_curve_close=${MANGO_ANIMATION_CURVE_CLOSE}
animation_curve_focus=${MANGO_ANIMATION_CURVE_FOCUS}
animation_curve_opafadeout=${MANGO_ANIMATION_CURVE_OPAFADEOUT}
animation_curve_opafadein=${MANGO_ANIMATION_CURVE_OPAFADEIN}

cursor_size=${MANGO_CURSOR_SIZE}
gappih=${MANGO_GAP_INNER_H}
gappiv=${MANGO_GAP_INNER_V}
gappoh=${MANGO_GAP_OUTER_H}
gappov=${MANGO_GAP_OUTER_V}
scratchpad_width_ratio=${MANGO_SCRATCHPAD_WIDTH_RATIO}
scratchpad_height_ratio=${MANGO_SCRATCHPAD_HEIGHT_RATIO}
borderpx=${MANGO_BORDER_PX}

rootcolor=${MANGO_ROOT_COLOR}
bordercolor=${MANGO_BORDER_COLOR}
focuscolor=${MANGO_FOCUS_COLOR}
maximizescreencolor=${MANGO_MAXIMIZE_COLOR}
urgentcolor=${MANGO_URGENT_COLOR}
scratchpadcolor=${MANGO_SCRATCHPAD_COLOR}
globalcolor=${MANGO_GLOBAL_COLOR}
overlaycolor=${MANGO_OVERLAY_COLOR}
EOF

if [[ "${mode}" == "check" ]]; then
  diff -u "${THEME_OUT}" "${tmp_theme}"
  exit 0
fi

install -D -m 644 "${tmp_theme}" "${THEME_OUT}"
