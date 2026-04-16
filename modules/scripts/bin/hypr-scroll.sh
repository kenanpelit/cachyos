#!/usr/bin/env bash
# ==============================================================================
# Script: hypr-scroll
# Description: Wrapper around core Hyprland scrolling layout dispatchers with fallbacks.
# Usage: hypr-scroll <subcommand> [args...]
# ==============================================================================
set -euo pipefail

CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/hypr-scroll"
STATE_FILE="${CACHE_DIR}/state"
CONF_RATIOS=(0.333 0.50 0.667 0.800 1.0)

usage() {
  cat <<'EOF'
usage:
  hypr-scroll move <+col|-col|+px|-px>
  hypr-scroll focus <l|r|u|d>
  hypr-scroll swapcol <l|r>
  hypr-scroll movewindowto <l|r|u|d>
  hypr-scroll colresize <value|+conf|-conf>
  hypr-scroll fit <active|visible|all|toend|tobeg>
  hypr-scroll togglefit
  hypr-scroll promote [l|r]
  hypr-scroll movecoltoworkspace <workspace>
EOF
}

ensure_cache_dir() {
  mkdir -p "$CACHE_DIR"
}

ensure_hypr_env() {
  : "${XDG_RUNTIME_DIR:="/run/user/$(id -u)"}"

  if [[ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]]; then
    return 0
  fi

  local sig
  sig="$(ls "$XDG_RUNTIME_DIR"/hypr 2>/dev/null | head -n1 || true)"
  if [[ -n "${sig:-}" ]]; then
    export HYPRLAND_INSTANCE_SIGNATURE="$sig"
  fi
}

using_scrolling_layout() {
  command -v hyprctl >/dev/null 2>&1 || return 1

  local option
  option="$(
    hyprctl getoption general:layout -j 2>/dev/null \
      || hyprctl getoption general:layout 2>/dev/null \
      || true
  )"

  grep -Eq '"str"[[:space:]]*:[[:space:]]*"scrolling"|str:[[:space:]]*"scrolling"' <<<"$option"
}

layoutmsg() {
  command -v hyprctl >/dev/null 2>&1 || return 127
  hyprctl dispatch layoutmsg "$*" >/dev/null 2>&1
}

dispatch() {
  command -v hyprctl >/dev/null 2>&1 || return 127
  hyprctl dispatch "$@" >/dev/null 2>&1
}

load_ratio_index() {
  local value="0"
  ensure_cache_dir
  if [[ -f "$STATE_FILE" ]]; then
    value="$(sed -n 's/^ratio_index=//p' "$STATE_FILE" | head -n1)"
  fi
  if [[ ! "$value" =~ ^[0-9]+$ ]]; then
    value="0"
  fi
  printf '%s\n' "$value"
}

save_ratio_index() {
  ensure_cache_dir
  printf 'ratio_index=%s\n' "$1" >"$STATE_FILE"
}

fallback_colresize() {
  local arg="$1"

  case "$arg" in
    +conf|-conf)
      local idx max
      idx="$(load_ratio_index)"
      max="${#CONF_RATIOS[@]}"
      if [[ "$arg" == "+conf" ]]; then
        idx=$(((idx + 1) % max))
      else
        idx=$(((idx - 1 + max) % max))
      fi
      save_ratio_index "$idx"
      dispatch splitratio "${CONF_RATIOS[$idx]}" || true
      ;;
    +*|-*|[0-9]*.[0-9]*|[0-9])
      dispatch splitratio "$arg" || true
      ;;
    *)
      return 0
      ;;
  esac
}

fallback_move() {
  local arg="$1"
  local dir=""

  case "$arg" in
    +col) dir="r" ;;
    -col) dir="l" ;;
    +*|[0-9]*)
      dir="r"
      ;;
    -*)
      dir="l"
      ;;
    *)
      return 0
      ;;
  esac

  dispatch movefocus "$dir" || true
}

fallback_fit() {
  local mode="${1:-active}"
  case "$mode" in
    toend)
      dispatch movefocus r || true
      ;;
    tobeg)
      dispatch movefocus l || true
      ;;
    active|visible|all)
      # No native equivalent in non-scrolling layouts; no-op.
      ;;
    *)
      return 0
      ;;
  esac
}

cmd="${1:-}"
shift || true

ensure_hypr_env

case "$cmd" in
  move)
    delta="${1:-}"
    [[ -n "$delta" ]] || { usage >&2; exit 2; }
    if using_scrolling_layout && layoutmsg "move $delta"; then
      exit 0
    fi
    fallback_move "$delta"
    ;;
  focus)
    dir="${1:-}"
    [[ -n "$dir" ]] || { usage >&2; exit 2; }
    if using_scrolling_layout && layoutmsg "focus $dir"; then
      exit 0
    fi
    exec hyprctl dispatch movefocus "$dir"
    ;;
  swapcol)
    dir="${1:-}"
    [[ -n "$dir" ]] || { usage >&2; exit 2; }
    if using_scrolling_layout && layoutmsg "swapcol $dir"; then
      exit 0
    fi
    dispatch swapwindow "$dir" || dispatch movewindow "$dir"
    ;;
  movewindowto)
    dir="${1:-}"
    [[ -n "$dir" ]] || { usage >&2; exit 2; }
    if using_scrolling_layout && layoutmsg "movewindowto $dir"; then
      exit 0
    fi
    dispatch movewindow "$dir"
    ;;
  colresize)
    value="${1:-}"
    [[ -n "$value" ]] || { usage >&2; exit 2; }
    if using_scrolling_layout && layoutmsg "colresize $value"; then
      exit 0
    fi
    fallback_colresize "$value"
    ;;
  fit)
    mode="${1:-active}"
    if using_scrolling_layout && layoutmsg "fit $mode"; then
      exit 0
    fi
    fallback_fit "$mode"
    ;;
  togglefit)
    if using_scrolling_layout && layoutmsg "togglefit"; then
      exit 0
    fi
    exit 0
    ;;
  promote)
    side="${1:-r}"
    if using_scrolling_layout && layoutmsg "promote"; then
      if [[ "$side" == "l" ]]; then
        layoutmsg "swapcol l" || true
      fi
      exit 0
    fi
    dispatch movewindow "$side" || true
    dispatch movefocus "$side" || true
    ;;
  movecoltoworkspace)
    target="${1:-}"
    [[ -n "$target" ]] || { usage >&2; exit 2; }
    if using_scrolling_layout && layoutmsg "movecoltoworkspace $target"; then
      exit 0
    fi
    dispatch movetoworkspace "$target"
    ;;
  ""|-h|--help|help)
    usage
    ;;
  *)
    usage >&2
    exit 2
    ;;
esac
