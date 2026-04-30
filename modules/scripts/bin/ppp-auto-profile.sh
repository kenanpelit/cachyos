#!/usr/bin/env bash
# ==============================================================================
# Script: ppp-auto-profile.sh
# Description: Periodic power profile chooser using live CPU usage samples
# Usage: ppp-auto-profile.sh [--help|--status]
# ==============================================================================
set -euo pipefail

# ppp-auto-profile
# Periodic power profile chooser for power-profiles-daemon.
#
# Behavior:
# - If lock file exists, do nothing.
# - If running on battery, never keep performance.
# - On AC: track live aggregate and per-core CPU busy time via /proc/stat.
# - Switch to performance on aggregate load or single-core bursts.
# - Switch back to balanced only after aggregate and per-core load are both low.
# - Respect a short cooldown after profile changes to avoid profile flapping.

STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/ppd-auto-profile"
LOCK_FILE="${STATE_DIR}/lock"
STATE_FILE="${STATE_DIR}/cpu-sample.state"
HIGH_AVG_BUSY_PERCENT="${PPP_HIGH_AVG_BUSY_PERCENT:-${PPP_HIGH_BUSY_PERCENT:-${PPP_HIGH_LOAD_PERCENT:-35}}}"
HIGH_MAX_BUSY_PERCENT="${PPP_HIGH_MAX_BUSY_PERCENT:-85}"
LOW_AVG_BUSY_PERCENT="${PPP_LOW_AVG_BUSY_PERCENT:-${PPP_LOW_BUSY_PERCENT:-${PPP_LOW_LOAD_PERCENT:-18}}}"
LOW_MAX_BUSY_PERCENT="${PPP_LOW_MAX_BUSY_PERCENT:-70}"
HIGH_STREAK_REQUIRED="${PPP_HIGH_STREAK_REQUIRED:-2}"
LOW_STREAK_REQUIRED="${PPP_LOW_STREAK_REQUIRED:-3}"
SWITCH_COOLDOWN_SEC="${PPP_SWITCH_COOLDOWN_SEC:-20}"
NOTIFY="${PPP_NOTIFY:-1}"

need() { command -v "$1" >/dev/null 2>&1; }

print_help() {
  cat <<EOF
ppp-auto-profile

Periodic power profile chooser for power-profiles-daemon.

Usage:
  ppp-auto-profile           Run one sampling/control pass
  ppp-auto-profile --status  Print current state and thresholds
  ppp-auto-profile --help    Show this help

Behavior:
  - Forces balanced on battery.
  - On AC, uses live aggregate and per-core CPU busy samples from /proc/stat.
  - Switches to performance when average CPU >= ${HIGH_AVG_BUSY_PERCENT}% or hottest core >= ${HIGH_MAX_BUSY_PERCENT}%.
  - Switches to balanced when average CPU <= ${LOW_AVG_BUSY_PERCENT}% and hottest core <= ${LOW_MAX_BUSY_PERCENT}%.
  - Uses a ${SWITCH_COOLDOWN_SEC}s cooldown after profile changes.

Environment overrides:
  PPP_HIGH_AVG_BUSY_PERCENT
  PPP_HIGH_MAX_BUSY_PERCENT
  PPP_LOW_AVG_BUSY_PERCENT
  PPP_LOW_MAX_BUSY_PERCENT
  PPP_HIGH_STREAK_REQUIRED
  PPP_LOW_STREAK_REQUIRED
  PPP_SWITCH_COOLDOWN_SEC
  PPP_NOTIFY
EOF
}

read_cpu_sample() {
  awk '
    /^cpu / {
      total = 0
      for (i = 2; i <= NF; i++) total += $i
      idle_total = $5 + $6
    }
    /^cpu[0-9]+ / {
      ctotal = 0
      for (i = 2; i <= NF; i++) ctotal += $i
      cidle = $5 + $6
      totals = totals sep ctotal
      idles = idles sep cidle
      sep = ","
    }
    END {
      printf "%s %s %s %s\n", total, idle_total, totals, idles
    }
  ' /proc/stat
}

calc_busy_pct() {
  local total="$1" idle="$2" prev_total="$3" prev_idle="$4"
  awk -v total="$total" -v idle="$idle" -v prev_total="$prev_total" -v prev_idle="$prev_idle" 'BEGIN {
    delta_total = total - prev_total
    delta_idle = idle - prev_idle
    if (delta_total <= 0 || delta_idle < 0) {
      print "unknown"
      exit
    }
    printf "%.2f", ((delta_total - delta_idle) / delta_total) * 100
  }'
}

calc_max_busy_pct() {
  local totals="$1" idles="$2" prev_totals="$3" prev_idles="$4"
  awk -v totals="$totals" -v idles="$idles" -v prev_totals="$prev_totals" -v prev_idles="$prev_idles" 'BEGIN {
    n = split(totals, ct, ",")
    split(idles, ci, ",")
    pn = split(prev_totals, pt, ",")
    split(prev_idles, pi, ",")
    if (n == 0 || pn != n) {
      print "unknown"
      exit
    }
    max = -1
    for (i = 1; i <= n; i++) {
      delta_total = ct[i] - pt[i]
      delta_idle = ci[i] - pi[i]
      if (delta_total <= 0 || delta_idle < 0) {
        continue
      }
      busy = ((delta_total - delta_idle) / delta_total) * 100
      if (busy > max) {
        max = busy
      }
    }
    if (max < 0) {
      print "unknown"
      exit
    }
    printf "%.2f", max
  }'
}

load_state() {
  prev_total=""
  prev_idle=""
  prev_cpu_totals=""
  prev_cpu_idles=""
  high_streak=0
  low_streak=0
  last_switch_epoch=0

  [[ -r "$STATE_FILE" ]] || return 0

  while IFS='=' read -r key value; do
    case "$key" in
      prev_total) prev_total="$value" ;;
      prev_idle) prev_idle="$value" ;;
      prev_cpu_totals) prev_cpu_totals="$value" ;;
      prev_cpu_idles) prev_cpu_idles="$value" ;;
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
prev_cpu_totals=$prev_cpu_totals
prev_cpu_idles=$prev_cpu_idles
high_streak=$high_streak
low_streak=$low_streak
last_switch_epoch=$last_switch_epoch
EOF
}

print_status() {
  local current source power avg_busy_pct="unknown" max_busy_pct="unknown"
  local total idle cpu_totals cpu_idles
  local prev_total prev_idle prev_cpu_totals prev_cpu_idles high_streak low_streak last_switch_epoch
  local last_switch_human="never"

  load_state

  if [[ -f "$LOCK_FILE" ]]; then
    source="locked"
  elif is_on_ac; then
    source="ac"
  else
    source="battery"
  fi

  if need powerprofilesctl; then
    current="$(powerprofilesctl get 2>/dev/null || true)"
  else
    current="unavailable"
  fi

  if [[ -n "${last_switch_epoch:-}" && "$last_switch_epoch" -gt 0 ]] && need date; then
    last_switch_human="$(date -d "@$last_switch_epoch" '+%F %T' 2>/dev/null || printf '%s' "$last_switch_epoch")"
  fi

  if [[ -r "$STATE_FILE" ]]; then
    read -r total idle cpu_totals cpu_idles < <(read_cpu_sample)
    if [[ -n "${prev_total:-}" && -n "${prev_idle:-}" ]]; then
      avg_busy_pct="$(calc_busy_pct "$total" "$idle" "$prev_total" "$prev_idle")"
    fi
    if [[ -n "${prev_cpu_totals:-}" && -n "${prev_cpu_idles:-}" ]]; then
      max_busy_pct="$(calc_max_busy_pct "$cpu_totals" "$cpu_idles" "$prev_cpu_totals" "$prev_cpu_idles")"
    fi
  fi

  cat <<EOF
ppp-auto-profile status
  Power source:        $source
  Current profile:     ${current:-unknown}
  CPU avg busy now:    $avg_busy_pct%
  CPU max core now:    $max_busy_pct%
  High threshold:      avg >= ${HIGH_AVG_BUSY_PERCENT}% or max >= ${HIGH_MAX_BUSY_PERCENT}% (${HIGH_STREAK_REQUIRED} samples)
  Low threshold:       avg <= ${LOW_AVG_BUSY_PERCENT}% and max <= ${LOW_MAX_BUSY_PERCENT}% (${LOW_STREAK_REQUIRED} samples)
  Cooldown:            ${SWITCH_COOLDOWN_SEC}s
  High streak:         ${high_streak:-0}
  Low streak:          ${low_streak:-0}
  Last switch:         $last_switch_human
  State file:          $STATE_FILE
  Lock file:           $LOCK_FILE
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
  # notify-send -t 1800 -i "$icon" "$title" "$reason" >/dev/null 2>&1 || true
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

  local current now total idle cpu_totals cpu_idles avg_busy_pct max_busy_pct
  local prev_total prev_idle prev_cpu_totals prev_cpu_idles high_streak low_streak last_switch_epoch
  current="$(powerprofilesctl get 2>/dev/null || true)"
  [[ -n "$current" ]] || exit 0
  now="$(date +%s)"
  mkdir -p "$STATE_DIR"
  load_state
  read -r total idle cpu_totals cpu_idles < <(read_cpu_sample)

  if ! is_on_ac; then
    if [[ "$current" == "performance" ]]; then
      powerprofilesctl set balanced >/dev/null 2>&1 || true
      notify_change balanced "Battery mode: switched from performance to balanced"
      last_switch_epoch="$now"
    fi
    prev_total="$total"
    prev_idle="$idle"
    prev_cpu_totals="$cpu_totals"
    prev_cpu_idles="$cpu_idles"
    high_streak=0
    low_streak=0
    save_state
    exit 0
  fi

  if [[ -z "${prev_total:-}" || -z "${prev_idle:-}" || -z "${prev_cpu_totals:-}" || -z "${prev_cpu_idles:-}" ]]; then
    prev_total="$total"
    prev_idle="$idle"
    prev_cpu_totals="$cpu_totals"
    prev_cpu_idles="$cpu_idles"
    save_state
    exit 0
  fi

  avg_busy_pct="$(calc_busy_pct "$total" "$idle" "$prev_total" "$prev_idle")"
  max_busy_pct="$(calc_max_busy_pct "$cpu_totals" "$cpu_idles" "$prev_cpu_totals" "$prev_cpu_idles")"
  prev_total="$total"
  prev_idle="$idle"
  prev_cpu_totals="$cpu_totals"
  prev_cpu_idles="$cpu_idles"

  if [[ "$avg_busy_pct" == "unknown" || "$max_busy_pct" == "unknown" ]]; then
    high_streak=0
    low_streak=0
    save_state
    exit 0
  fi

  if awk -v avg="$avg_busy_pct" -v max="$max_busy_pct" \
      -v high_avg="$HIGH_AVG_BUSY_PERCENT" -v high_max="$HIGH_MAX_BUSY_PERCENT" \
      'BEGIN { exit !((avg >= high_avg) || (max >= high_max)) }'; then
    high_streak=$((high_streak + 1))
    if (( high_streak > HIGH_STREAK_REQUIRED )); then
      high_streak="$HIGH_STREAK_REQUIRED"
    fi
    low_streak=0
  elif awk -v avg="$avg_busy_pct" -v max="$max_busy_pct" \
      -v low_avg="$LOW_AVG_BUSY_PERCENT" -v low_max="$LOW_MAX_BUSY_PERCENT" \
      'BEGIN { exit !((avg <= low_avg) && (max <= low_max)) }'; then
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
        "CPU avg: ${avg_busy_pct}%, max core: ${max_busy_pct}% (${high_streak}/${HIGH_STREAK_REQUIRED})"
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
        "CPU avg: ${avg_busy_pct}%, max core: ${max_busy_pct}% (${low_streak}/${LOW_STREAK_REQUIRED})"
      last_switch_epoch="$now"
      high_streak=0
      low_streak=0
      save_state
    exit 0
  fi

  save_state
}

case "${1:-}" in
  "" )
    main
    ;;
  -h|--help|help )
    print_help
    ;;
  -s|--status|status )
    print_status
    ;;
  * )
    printf 'Unknown option: %s\n\n' "$1" >&2
    print_help >&2
    exit 1
    ;;
esac
