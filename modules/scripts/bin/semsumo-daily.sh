#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# semsumo-daily
# Unified SemsuMo daily launcher for compositor keybinds (Hyprland + Niri).
#
# Purpose:
# - Keep keybind commands identical across compositors.
# - Resolve `semsumo` reliably even with minimal WM PATH.
# - Write execution logs and show desktop notifications on failure.
# -----------------------------------------------------------------------------

set -euo pipefail

export PATH="$HOME/.local/bin:$HOME/bin:/usr/local/bin:/usr/bin:/bin:${PATH:-}"

detect_session() {
  case "${XDG_CURRENT_DESKTOP:-}" in
  *Hyprland* | *hyprland*) printf '%s\n' "hyprland" ;;
  *niri* | *Niri*) printf '%s\n' "niri" ;;
  *)
    if command -v hyprctl >/dev/null 2>&1 && hyprctl version >/dev/null 2>&1; then
      printf '%s\n' "hyprland"
    elif [[ -n "${NIRI_SOCKET:-}" ]]; then
      printf '%s\n' "niri"
    else
      printf '%s\n' "generic"
    fi
    ;;
  esac
}

SESSION_NAME="$(detect_session)"
LOG_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/semsumo"
LOG_FILE="${LOG_DIR}/semsumo-daily-${SESSION_NAME}.log"
mkdir -p "$LOG_DIR" 2>/dev/null || true

notify_err() {
  local msg="${1:-Unknown error}"
  if command -v notify-send >/dev/null 2>&1; then
    notify-send -u critical "SemsuMo Daily" "$msg" 2>/dev/null || true
  fi
}

runner=""
if command -v semsumo >/dev/null 2>&1; then
  runner="$(command -v semsumo)"
elif [[ -x "$HOME/.local/bin/semsumo" ]]; then
  runner="$HOME/.local/bin/semsumo"
fi

if [[ -z "$runner" ]]; then
  notify_err "semsumo komutu bulunamadı (~/.local/bin/semsumo)."
  exit 127
fi

{
  printf '[%s] session=%s launch start\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$SESSION_NAME"
  printf 'runner=%s\n' "$runner"
} >>"$LOG_FILE" 2>/dev/null || true

if ! "$runner" launch --daily --concurrent >>"$LOG_FILE" 2>&1; then
  notify_err "semsumo launch başarısız. Log: $LOG_FILE"
  exit 1
fi
