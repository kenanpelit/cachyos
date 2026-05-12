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

expand_path() {
  local p="$1"
  case "$p" in
    # `${p#"~/"}` — quoted pattern in parameter expansion (bash 4.4+).
    # Without the quotes, `~` would be tilde-expanded BEFORE pattern
    # matching, so the prefix never matches and the literal `~/`
    # stays in the path → `$HOME/~/foo`.
    "~/"*) printf '%s\n' "${HOME}/${p#"~/"}" ;;
    "~")   printf '%s\n' "$HOME" ;;
    *)     printf '%s\n' "$p" ;;
  esac
}

# Lowest set bit position (1-indexed) of an integer — `mctl outputs --json`
# active_tag_mask is a bitmask, but mshell.toml [wallpaper.tags] keys are
# 1-based tag numbers. Tag mask 2 (=0b10) → tag 2; mask 4 → tag 3.
# Note: bash precedence — `==` binds tighter than `&`, so we MUST
# parenthesise the bitwise op or the loop never enters (`2 & 1 == 0`
# becomes `2 & (1 == 0)` = `2 & 0` = 0, falsy).
mask_to_tag() {
  local mask="$1" i=1
  while (( (mask & 1) == 0 && i < 32 )); do
    mask=$(( mask >> 1 ))
    i=$(( i + 1 ))
  done
  echo "$i"
}

resolve_wallpaper() {
  local arg="${1:-}"
  if [[ -n "$arg" ]]; then
    printf '%s\n' "$arg"
    return
  fi

  command -v mctl >/dev/null 2>&1 || die "mctl yok ve argüman verilmedi"
  command -v jq   >/dev/null 2>&1 || die "jq yok"

  # 1) margo state.json — eski tag-rule based wallpaper (genelde boş;
  #    mshell wallpaper'ı kendi çiziyor, margo bilgisi tutmuyor).
  local from_margo
  from_margo="$(mctl outputs --json 2>/dev/null \
    | jq -r '.[] | select(.active) | .wallpaper' \
    | head -n1)"
  if [[ -n "$from_margo" && "$from_margo" != "null" ]]; then
    printf '%s\n' "$from_margo"
    return
  fi

  # 2) mshell.toml [wallpaper.tags] map + aktif tag — mshell-owned path.
  local mshell_toml="${HOME}/.config/margo/mshell.toml"
  [[ -f "$mshell_toml" ]] || die "mshell.toml bulunamadı: $mshell_toml"

  local active_mask tag
  active_mask="$(mctl outputs --json 2>/dev/null \
    | jq -r '.[] | select(.active) | .active_tag_mask' \
    | head -n1)"
  [[ -n "$active_mask" && "$active_mask" != "null" ]] || die "Aktif tag mask okunamadı"
  tag="$(mask_to_tag "$active_mask")"

  # `[wallpaper.tags]` bloğundan "<tag>" = "..." satırını çek.
  local raw
  raw="$(awk -v tag="\"$tag\"" '
    /^\[wallpaper\.tags\]/ { in_block = 1; next }
    /^\[/                 { in_block = 0 }
    in_block && $1 == tag {
      sub(/^[^=]*=[[:space:]]*/, "")
      gsub(/^"|"$/, "")
      print
      exit
    }
  ' "$mshell_toml")"

  [[ -n "$raw" ]] || die "Tag $tag için [wallpaper.tags] girdisi yok"
  expand_path "$raw"
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
