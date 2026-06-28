#!/usr/bin/env bash
# ==============================================================================
# Script: semsumo-daily.sh
# Description: Unified SemsuMo daily launcher for compositor keybinds
# Usage: semsumo-daily.sh
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMMON_HELPER="${SCRIPT_DIR}/wayland-session-common.sh"
[[ -r "${COMMON_HELPER}" ]] || COMMON_HELPER="${SCRIPT_DIR}/wayland-session-common"
if [[ -r "${COMMON_HELPER}" ]]; then
  # shellcheck source=wayland-session-common.sh
  source "${COMMON_HELPER}"
  session_common_backfill_visual_env
fi

export PATH="$HOME/.local/bin:$HOME/bin:/usr/local/bin:/usr/bin:/bin:${PATH:-}"
SEMSUMO_DAILY_POWER_PROFILE="${SEMSUMO_DAILY_POWER_PROFILE:-performance}"

detect_session() {
  case "${XDG_CURRENT_DESKTOP:-}" in
  *margo* | *Margo*) printf '%s\n' "margo" ;;
  *)
    if command -v mctl >/dev/null 2>&1 && mctl status >/dev/null 2>&1; then
      printf '%s\n' "margo"
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

notify_info() {
  local msg="${1:-Done}"
  if command -v notify-send >/dev/null 2>&1; then
    notify-send -u low "SemsuMo Daily" "$msg" 2>/dev/null || true
  fi
}

prepare_power_profile() {
  local profile="${SEMSUMO_DAILY_POWER_PROFILE:-performance}"
  local current=""

  case "${profile,,}" in
  "" | off | none | skip | disabled)
    return 0
    ;;
  esac

  command -v powerprofilesctl >/dev/null 2>&1 || return 0
  current="$(powerprofilesctl get 2>/dev/null || true)"
  [[ "$current" == "$profile" ]] && return 0

  if powerprofilesctl set "$profile" >/dev/null 2>&1; then
    if [[ "${profile,,}" == "performance" ]]; then
      notify_info "Power profile switched to Performance"
    else
      notify_info "Power profile switched to ${profile}"
    fi
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

prepare_power_profile
printf '[%s] power_profile=%s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$SEMSUMO_DAILY_POWER_PROFILE" >>"$LOG_FILE" 2>/dev/null || true

if ! "$runner" launch --daily --concurrent >>"$LOG_FILE" 2>&1; then
  notify_err "semsumo launch başarısız. Log: $LOG_FILE"
  exit 1
fi
