#!/usr/bin/env bash
# hypr-semsumo-daily - Hyprland keybind wrapper for semsumo daily launch
#
# Why:
# - Keep Hypr bind line simple and stable.
# - Ensure command resolution works even when session PATH differs.
# - Emit a desktop notification if semsumo is missing.

set -euo pipefail

export PATH="$HOME/.local/bin:$HOME/bin:/usr/local/bin:/usr/bin:/bin:${PATH:-}"

LOG_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/hypr"
LOG_FILE="${LOG_DIR}/hypr-semsumo-daily.log"
mkdir -p "$LOG_DIR" 2>/dev/null || true

notify_err() {
  local msg="${1:-Unknown error}"
  if command -v notify-send >/dev/null 2>&1; then
    notify-send -u critical "Hypr Semsumo" "$msg" 2>/dev/null || true
  fi
}

runner=""
if command -v semsumo >/dev/null 2>&1; then
  runner="$(command -v semsumo)"
elif [[ -x "$HOME/.local/bin/semsumo" ]]; then
  runner="$HOME/.local/bin/semsumo"
fi

if [[ -z "$runner" ]]; then
  notify_err "semsumo bulunamadı (~/.local/bin/semsumo)."
  exit 127
fi

{
  printf '[%s] launch start\n' "$(date '+%Y-%m-%d %H:%M:%S')"
  printf 'runner=%s\n' "$runner"
} >>"$LOG_FILE" 2>/dev/null || true

if ! "$runner" launch --daily --concurrent >>"$LOG_FILE" 2>&1; then
  notify_err "semsumo launch başarısız. Log: $LOG_FILE"
  exit 1
fi
