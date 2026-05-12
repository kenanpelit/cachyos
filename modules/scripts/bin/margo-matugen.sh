#!/usr/bin/env bash
# ==============================================================================
# Script: margo-matugen.sh
# Description: Run matugen against a wallpaper, render margo + mshell color
#              templates, reload margo so the new palette takes effect.
# Usage: margo-matugen [wallpaper]
#
# Without an argument the active output's wallpaper is fetched from
# `mctl outputs --json`. With an argument, that path is used directly.
# ==============================================================================

set -euo pipefail

MATUGEN_CONFIG="${MATUGEN_CONFIG:-$HOME/.config/margo/matugen/config.toml}"
SCHEME_MODE="${MARGO_MATUGEN_MODE:-dark}"           # dark / light
SCHEME_TYPE="${MARGO_MATUGEN_TYPE:-scheme-tonal-spot}"
SCHEME_PREFER="${MARGO_MATUGEN_PREFER:-saturation}" # darkness/lightness/saturation/less-saturation/value/closest-to-fallback

die() { echo "margo-matugen: $*" >&2; notify-send "margo-matugen" "$*" -t 2000 2>/dev/null || true; exit 1; }

resolve_wallpaper() {
  local arg="${1:-}"
  if [[ -n "$arg" ]]; then
    printf '%s\n' "$arg"
    return
  fi
  command -v mctl >/dev/null 2>&1 || die "mctl yok ve argüman verilmedi"
  command -v jq   >/dev/null 2>&1 || die "jq yok"
  mctl outputs --json 2>/dev/null \
    | jq -r '.[] | select(.active) | .wallpaper' \
    | head -n1
}

WALLPAPER="$(resolve_wallpaper "${1:-}")"
[[ -n "$WALLPAPER" && "$WALLPAPER" != "null" ]] || die "Aktif duvar kâğıdı bulunamadı"
[[ -f "$WALLPAPER" ]] || die "Dosya yok: $WALLPAPER"

[[ -f "$MATUGEN_CONFIG" ]] || die "matugen config bulunamadı: $MATUGEN_CONFIG"

command -v matugen >/dev/null 2>&1 || die "matugen yüklü değil"

mkdir -p "$HOME/.cache/margo"

matugen image "$WALLPAPER" \
  -c "$MATUGEN_CONFIG" \
  --mode "$SCHEME_MODE" \
  --type "$SCHEME_TYPE" \
  --prefer "$SCHEME_PREFER" \
  -q

# `mctl reload` margo'ya config'i yeniden okutur — matugen yeni colors
# dosyasını yazdığı için margo onları source ettiğinde palet yenilenir.
# mshell şu an matugen output'unu otomatik load etmiyor (sonraki tur).
if command -v mctl >/dev/null 2>&1; then
  mctl reload >/dev/null 2>&1 || true
fi

notify-send "🎨 margo-matugen" "$(basename "$WALLPAPER") → tema güncellendi" -t 2500 2>/dev/null || true
echo "margo-matugen: $WALLPAPER → palette renderlandı, mctl reload tetiklendi"
