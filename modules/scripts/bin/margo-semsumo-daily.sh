#!/usr/bin/env bash
# ==============================================================================
# Script: margo-semsumo-daily.sh
# Description:
#   Margo-only variant of `semsumo-daily.sh`. Hands the full daily launch
#   off to `uwsm app` so every child (browsers, terminal, electron clients)
#   lands inside a transient systemd scope under `graphical-session.target`:
#
#     * Single cgroup for the whole batch — clean SIGTERM on margo quit,
#       no zombie helium/electron renderers after logout.
#     * Logs go to journald (`journalctl --user -u app-uwsm-semsumo-daily-*`)
#       in addition to ~/.local/state/semsumo/.
#     * `XDG_CURRENT_DESKTOP=margo` is preserved through systemd
#       --user activation so portals that key off it (xdg-desktop-portal,
#       gnome-keyring) authenticate against the right session.
#
# Usage: bind = super+alt,Return,spawn,margo-semsumo-daily
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

# ── Margo guard ─────────────────────────────────────────────────────────────
# Refuse to run on non-margo sessions; the upstream `semsumo-daily.sh`
# handles hyprland/niri/generic. Avoids accidental dual-launch when the
# bind survives a session-manager switch.
case "${XDG_CURRENT_DESKTOP:-}" in
*margo* | *Margo*) ;;
*)
  if ! command -v mctl >/dev/null 2>&1 || ! mctl status >/dev/null 2>&1; then
    echo "margo-semsumo-daily: not in a margo session, refusing to run" >&2
    exit 0
  fi
  ;;
esac

LOG_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/semsumo"
LOG_FILE="${LOG_DIR}/semsumo-daily-margo.log"
mkdir -p "$LOG_DIR" 2>/dev/null || true

notify_err() {
  command -v notify-send >/dev/null 2>&1 &&
    notify-send -u critical "SemsuMo Daily" "${1:-Unknown error}" 2>/dev/null || true
}
notify_info() {
  command -v notify-send >/dev/null 2>&1 &&
    notify-send -u low "SemsuMo Daily" "${1:-Done}" 2>/dev/null || true
}

# ── Power profile ───────────────────────────────────────────────────────────
prepare_power_profile() {
  local profile="${SEMSUMO_DAILY_POWER_PROFILE:-performance}"
  case "${profile,,}" in
  "" | off | none | skip | disabled) return 0 ;;
  esac
  command -v powerprofilesctl >/dev/null 2>&1 || return 0
  local current
  current="$(powerprofilesctl get 2>/dev/null || true)"
  [[ "$current" == "$profile" ]] && return 0
  if powerprofilesctl set "$profile" >/dev/null 2>&1; then
    [[ "${profile,,}" == "performance" ]] &&
      notify_info "Power profile switched to Performance" ||
      notify_info "Power profile switched to ${profile}"
  fi
}

# ── Locate semsumo runner ───────────────────────────────────────────────────
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

# ── uwsm guard ──────────────────────────────────────────────────────────────
# Without uwsm the script still works (falls back to direct spawn) — useful
# during early boot or rescue sessions. Optional dep, not hard requirement.
uwsm_bin=""
if command -v uwsm >/dev/null 2>&1; then
  uwsm_bin="$(command -v uwsm)"
fi

# ── Logging header ──────────────────────────────────────────────────────────
{
  printf '[%s] session=margo launch start\n' "$(date '+%Y-%m-%d %H:%M:%S')"
  printf 'runner=%s\n' "$runner"
  printf 'uwsm=%s\n' "${uwsm_bin:-(unavailable, falling back to direct spawn)}"
} >>"$LOG_FILE" 2>/dev/null || true

prepare_power_profile
printf '[%s] power_profile=%s\n' "$(date '+%Y-%m-%d %H:%M:%S')" \
  "$SEMSUMO_DAILY_POWER_PROFILE" >>"$LOG_FILE" 2>/dev/null || true

# ── Launch ──────────────────────────────────────────────────────────────────
# `--concurrent` lets semsumo fan out daily profiles in parallel under the
# single uwsm scope; the scope inherits to every child via cgroup, so a
# logout SIGTERM cascades cleanly.
#
# `-a semsumo-daily` is the systemd unit name. Stays unique across re-runs
# because uwsm appends a random suffix internally
# (`app-uwsm-semsumo-daily-<RAND>.scope`). Inspect with:
#   systemctl --user status 'app-uwsm-semsumo-daily-*.scope'
#   journalctl --user -u 'app-uwsm-semsumo-daily-*.scope' -f
launch_args=(launch --daily --concurrent)

if [[ -n "$uwsm_bin" ]]; then
  if ! "$uwsm_bin" app -a semsumo-daily -- "$runner" "${launch_args[@]}" \
    >>"$LOG_FILE" 2>&1; then
    notify_err "uwsm app -a semsumo-daily başarısız. Log: $LOG_FILE"
    exit 1
  fi
else
  # Fallback: direct spawn (margo is parent, no scope isolation).
  if ! "$runner" "${launch_args[@]}" >>"$LOG_FILE" 2>&1; then
    notify_err "semsumo launch başarısız. Log: $LOG_FILE"
    exit 1
  fi
fi
