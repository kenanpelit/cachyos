#!/usr/bin/env bash
# ==============================================================================
# Script: hypr-scroll
# Description: Wrapper around hyprscrolling layout dispatchers with fallbacks.
# Usage: hypr-scroll <subcommand> [args...]
# ==============================================================================
set -euo pipefail

CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/hypr-scroll"
STATE_FILE="${CACHE_DIR}/state"
CONF_RATIOS=(0.30 0.45 0.60 0.75 1.0)

usage() {
  cat <<'EOF'
usage:
  hypr-scroll focus <l|r|u|d>
  hypr-scroll swapcol <l|r>
  hypr-scroll movewindowto <l|r|u|d>
  hypr-scroll colresize <value|+conf|-conf>
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

have_hyprscrolling() {
  command -v hyprctl >/dev/null 2>&1 || return 1
  hyprctl plugin list 2>/dev/null | grep -qi "hyprscrolling"
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

cmd="${1:-}"
shift || true

ensure_hypr_env

case "$cmd" in
  focus)
    dir="${1:-}"
    [[ -n "$dir" ]] || { usage >&2; exit 2; }
    if have_hyprscrolling && layoutmsg "focus $dir"; then
      exit 0
    fi
    exec hyprctl dispatch movefocus "$dir"
    ;;
  swapcol)
    dir="${1:-}"
    [[ -n "$dir" ]] || { usage >&2; exit 2; }
    if have_hyprscrolling && layoutmsg "swapcol $dir"; then
      exit 0
    fi
    dispatch swapwindow "$dir" || dispatch movewindow "$dir"
    ;;
  movewindowto)
    dir="${1:-}"
    [[ -n "$dir" ]] || { usage >&2; exit 2; }
    if have_hyprscrolling && layoutmsg "movewindowto $dir"; then
      exit 0
    fi
    dispatch movewindow "$dir"
    ;;
  colresize)
    value="${1:-}"
    [[ -n "$value" ]] || { usage >&2; exit 2; }
    if have_hyprscrolling && layoutmsg "colresize $value"; then
      exit 0
    fi
    fallback_colresize "$value"
    ;;
  togglefit)
    if have_hyprscrolling && layoutmsg "togglefit"; then
      exit 0
    fi
    exit 0
    ;;
  promote)
    side="${1:-r}"
    if have_hyprscrolling; then
      layoutmsg "promote" || true
      if [[ "$side" == "l" ]]; then
        layoutmsg "swapcol l" || true
      fi
    fi
    ;;
  movecoltoworkspace)
    target="${1:-}"
    [[ -n "$target" ]] || { usage >&2; exit 2; }
    if have_hyprscrolling && layoutmsg "movecoltoworkspace $target"; then
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
