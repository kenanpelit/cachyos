#!/usr/bin/env bash
set -euo pipefail

# ppp-auto-profile
# Periodic power profile chooser for power-profiles-daemon.
#
# Behavior:
# - If lock file exists, do nothing.
# - If running on battery, never keep performance.
# - On AC: switch to performance on high load, back to balanced on low load.

LOCK_FILE="${HOME}/.local/state/ppd-auto-profile/lock"
HIGH_LOAD_PERCENT="${PPP_HIGH_LOAD_PERCENT:-70}"
LOW_LOAD_PERCENT="${PPP_LOW_LOAD_PERCENT:-35}"
NOTIFY="${PPP_NOTIFY:-1}"

need() { command -v "$1" >/dev/null 2>&1; }

notify_change() {
  local profile="$1" reason="$2" icon title
  [[ "$NOTIFY" == "1" ]] || return 0
  need notify-send || return 0

  case "$profile" in
    performance) icon="speedometer"; title="Power Profile: Performance" ;;
    balanced) icon="battery-good"; title="Power Profile: Balanced" ;;
    *) icon="battery-good"; title="Power Profile: $profile" ;;
  esac
  notify-send -t 3000 -i "$icon" "$title" "$reason" >/dev/null 2>&1 || true
}

is_on_ac() {
  local t p mains_found=0
  for t in /sys/class/power_supply/*/type; do
    [[ -r "$t" ]] || continue
    if [[ "$(cat "$t" 2>/dev/null || true)" == "Mains" ]]; then
      mains_found=1
      p="${t%/type}/online"
      [[ -r "$p" ]] || continue
      [[ "$(cat "$p" 2>/dev/null || echo 0)" == "1" ]] && return 0
    fi
  done

  # Fallback for systems without explicit Mains type.
  if [[ "$mains_found" -eq 0 ]]; then
    for p in /sys/class/power_supply/*/online; do
      [[ -r "$p" ]] || continue
      [[ "$(cat "$p" 2>/dev/null || echo 0)" == "1" ]] && return 0
    done
  fi
  return 1
}

main() {
  need powerprofilesctl || exit 0
  need awk || exit 0
  need nproc || exit 0

  [[ -f "$LOCK_FILE" ]] && exit 0

  local current cpus load1 load_pct
  current="$(powerprofilesctl get 2>/dev/null || true)"
  [[ -n "$current" ]] || exit 0

  if ! is_on_ac; then
    if [[ "$current" == "performance" ]]; then
      powerprofilesctl set balanced >/dev/null 2>&1 || true
      notify_change balanced "Battery mode: switched from performance to balanced"
    fi
    exit 0
  fi

  cpus="$(nproc --all 2>/dev/null || echo 1)"
  load1="$(awk '{print $1}' /proc/loadavg)"
  load_pct="$(awk -v l="$load1" -v c="$cpus" 'BEGIN { if (c < 1) c = 1; printf "%.2f", (l / c) * 100 }')"

  if awk -v lp="$load_pct" -v high="$HIGH_LOAD_PERCENT" 'BEGIN { exit !(lp >= high) }'; then
    if [[ "$current" != "performance" ]]; then
      powerprofilesctl set performance >/dev/null 2>&1 || true
      notify_change performance "High load: ${load_pct}% (threshold: ${HIGH_LOAD_PERCENT}%)"
    fi
    exit 0
  fi

  if awk -v lp="$load_pct" -v low="$LOW_LOAD_PERCENT" 'BEGIN { exit !(lp <= low) }'; then
    if [[ "$current" == "performance" ]]; then
      powerprofilesctl set balanced >/dev/null 2>&1 || true
      notify_change balanced "Load normalized: ${load_pct}% (threshold: ${LOW_LOAD_PERCENT}%)"
    fi
  fi
}

main "$@"
