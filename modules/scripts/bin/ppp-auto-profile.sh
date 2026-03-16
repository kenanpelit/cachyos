#!/usr/bin/env bash
# ==============================================================================
# Script: ppp-auto-profile.sh
# Description: Periodic power profile chooser using live CPU usage samples
# Usage: ppp-auto-profile.sh
# ==============================================================================
set -euo pipefail

# ppp-auto-profile
# Periodic power profile chooser for power-profiles-daemon.
#
# Behavior:
# - If lock file exists, do nothing.
# - If running on battery, never keep performance.
# - On AC: track live CPU busy time via /proc/stat.
# - Switch to performance only after consecutive high-usage samples.
# - Switch back to balanced only after consecutive low-usage samples.
# - Respect a short cooldown after profile changes to avoid profile flapping.

STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/ppd-auto-profile"
LOCK_FILE="${STATE_DIR}/lock"
STATE_FILE="${STATE_DIR}/cpu-sample.state"
HIGH_BUSY_PERCENT="${PPP_HIGH_BUSY_PERCENT:-${PPP_HIGH_LOAD_PERCENT:-50}}"
LOW_BUSY_PERCENT="${PPP_LOW_BUSY_PERCENT:-${PPP_LOW_LOAD_PERCENT:-30}}"
HIGH_STREAK_REQUIRED="${PPP_HIGH_STREAK_REQUIRED:-2}"
LOW_STREAK_REQUIRED="${PPP_LOW_STREAK_REQUIRED:-3}"
SWITCH_COOLDOWN_SEC="${PPP_SWITCH_COOLDOWN_SEC:-60}"
NOTIFY="${PPP_NOTIFY:-1}"

need() { command -v "$1" >/dev/null 2>&1; }

read_cpu_sample() {
  local user nice system idle iowait irq softirq steal total idle_total
  read -r _ user nice system idle iowait irq softirq steal _ < /proc/stat
  total=$((user + nice + system + idle + iowait + irq + softirq + steal))
  idle_total=$((idle + iowait))
  printf '%s %s\n' "$total" "$idle_total"
}

load_state() {
  prev_total=""
  prev_idle=""
  high_streak=0
  low_streak=0
  last_switch_epoch=0

  [[ -r "$STATE_FILE" ]] || return 0

  while IFS='=' read -r key value; do
    case "$key" in
      prev_total) prev_total="$value" ;;
      prev_idle) prev_idle="$value" ;;
      high_streak) high_streak="$value" ;;
      low_streak) low_streak="$value" ;;
      last_switch_epoch) last_switch_epoch="$value" ;;
    esac
  done < "$STATE_FILE"
}

save_state() {
  mkdir -p "$STATE_DIR"
  cat > "$STATE_FILE" <<EOF
prev_total=$prev_total
prev_idle=$prev_idle
high_streak=$high_streak
low_streak=$low_streak
last_switch_epoch=$last_switch_epoch
EOF
}

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
  need date || exit 0

  [[ -f "$LOCK_FILE" ]] && exit 0

  local current now total idle delta_total delta_idle busy_pct
  local prev_total prev_idle high_streak low_streak last_switch_epoch
  current="$(powerprofilesctl get 2>/dev/null || true)"
  [[ -n "$current" ]] || exit 0
  now="$(date +%s)"
  mkdir -p "$STATE_DIR"
  load_state
  read -r total idle < <(read_cpu_sample)

  if ! is_on_ac; then
    if [[ "$current" == "performance" ]]; then
      powerprofilesctl set balanced >/dev/null 2>&1 || true
      notify_change balanced "Battery mode: switched from performance to balanced"
      last_switch_epoch="$now"
    fi
    prev_total="$total"
    prev_idle="$idle"
    high_streak=0
    low_streak=0
    save_state
    exit 0
  fi

  if [[ -z "${prev_total:-}" || -z "${prev_idle:-}" ]]; then
    prev_total="$total"
    prev_idle="$idle"
    save_state
    exit 0
  fi

  delta_total=$((total - prev_total))
  delta_idle=$((idle - prev_idle))
  prev_total="$total"
  prev_idle="$idle"

  if (( delta_total <= 0 || delta_idle < 0 )); then
    high_streak=0
    low_streak=0
    save_state
    exit 0
  fi

  busy_pct="$(awk -v total="$delta_total" -v idle="$delta_idle" 'BEGIN {
    printf "%.2f", ((total - idle) / total) * 100
  }')"

  if awk -v cpu="$busy_pct" -v high="$HIGH_BUSY_PERCENT" 'BEGIN { exit !(cpu >= high) }'; then
    high_streak=$((high_streak + 1))
    if (( high_streak > HIGH_STREAK_REQUIRED )); then
      high_streak="$HIGH_STREAK_REQUIRED"
    fi
    low_streak=0
  elif awk -v cpu="$busy_pct" -v low="$LOW_BUSY_PERCENT" 'BEGIN { exit !(cpu <= low) }'; then
    low_streak=$((low_streak + 1))
    if (( low_streak > LOW_STREAK_REQUIRED )); then
      low_streak="$LOW_STREAK_REQUIRED"
    fi
    high_streak=0
  else
    high_streak=0
    low_streak=0
  fi

  if (( now - last_switch_epoch >= SWITCH_COOLDOWN_SEC )) && \
     (( high_streak >= HIGH_STREAK_REQUIRED )) && \
     [[ "$current" != "performance" ]]; then
      powerprofilesctl set performance >/dev/null 2>&1 || true
      notify_change performance \
        "CPU busy: ${busy_pct}% (${high_streak}/${HIGH_STREAK_REQUIRED}, threshold: ${HIGH_BUSY_PERCENT}%)"
      last_switch_epoch="$now"
      high_streak=0
      low_streak=0
      save_state
      exit 0
  fi

  if (( now - last_switch_epoch >= SWITCH_COOLDOWN_SEC )) && \
     (( low_streak >= LOW_STREAK_REQUIRED )) && \
     [[ "$current" == "performance" ]]; then
      powerprofilesctl set balanced >/dev/null 2>&1 || true
      notify_change balanced \
        "CPU normalized: ${busy_pct}% (${low_streak}/${LOW_STREAK_REQUIRED}, threshold: ${LOW_BUSY_PERCENT}%)"
      last_switch_epoch="$now"
      high_streak=0
      low_streak=0
      save_state
    exit 0
  fi

  save_state
}

main "$@"
