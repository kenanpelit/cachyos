#!/usr/bin/env bash
# ==============================================================================
# Script: sunsetr-set.sh
# Description: Native preset scheduler/helper for the sunsetr Wayland service
# Usage: sunsetr-set.sh [list|auto|apply|status|<preset>] [options]
# ==============================================================================
set -euo pipefail

SCRIPT_NAME="$(basename "$0")"
CONFIG_ROOT="${XDG_CONFIG_HOME:-$HOME/.config}/sunsetr"
DEFAULT_CONFIG_ROOT="${XDG_CONFIG_HOME:-$HOME/.config}/sunsetr"
SCHEDULE_FILE="$CONFIG_ROOT/schedule.conf"
NOTIFY_ENABLED=1
APPLY_AFTER_SET=0
declare -a SCHEDULE_STARTS=()
declare -a SCHEDULE_START_KEYS=()
declare -a SCHEDULE_PRESETS=()

usage() {
  cat <<EOF
$SCRIPT_NAME - Sunsetr preset scheduler/helper

Usage:
  $SCRIPT_NAME list
  $SCRIPT_NAME auto
  $SCRIPT_NAME apply
  $SCRIPT_NAME status
  $SCRIPT_NAME <preset>

Options:
  --apply                 Apply the selected preset to a running sunsetr instance
  --no-notify             Disable desktop notifications
  -h, --help              Show help

Config:
  Default config root: $CONFIG_ROOT
  Schedule manifest:   $SCHEDULE_FILE

Examples:
  $SCRIPT_NAME auto --apply
  $SCRIPT_NAME 2100-dusk
  $SCRIPT_NAME dusk --apply
  $SCRIPT_NAME apply
  $SCRIPT_NAME status
EOF
}

log() {
  printf '[sunsetr-set] %s\n' "$*"
}

warn() {
  printf '[sunsetr-set] WARN: %s\n' "$*" >&2
}

die() {
  printf '[sunsetr-set] ERROR: %s\n' "$*" >&2
  exit 1
}

notify() {
  local title="$1"
  local body="$2"
  [[ "$NOTIFY_ENABLED" -eq 1 ]] || return 0
  command -v notify-send >/dev/null 2>&1 || return 0
  notify-send -t 1600 "$title" "$body" >/dev/null 2>&1 || true
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "missing dependency: $1"
}

config_root_canonical() {
  if [[ -d "$CONFIG_ROOT" ]]; then
    (cd "$CONFIG_ROOT" && pwd -P)
  else
    printf '%s\n' "$CONFIG_ROOT"
  fi
}

preset_alias() {
  case "${1,,}" in
    default | base)
      printf 'default\n'
      ;;
    0730 | 07:30 | morning)
      printf '0730-morning\n'
      ;;
    1000 | 10:00 | late-morning | latemorning)
      printf '1000-late-morning\n'
      ;;
    1300 | 13:00 | noon | midday | day)
      printf '1300-noon\n'
      ;;
    1700 | 17:00 | afternoon)
      printf '1700-afternoon\n'
      ;;
    1830 | 18:30 | 1900 | 19:00 | sunset)
      printf '1900-sunset\n'
      ;;
    2030 | 20:30 | 2100 | 21:00 | dusk)
      printf '2100-dusk\n'
      ;;
    2200 | 22:00 | 2230 | 22:30 | evening)
      printf '2230-evening\n'
      ;;
    2330 | 23:30 | 0000 | 00:00 | night | midnight)
      printf '0000-night\n'
      ;;
    0130 | 01:30 | 0200 | 02:00 | late-night | latenight)
      printf '0200-late-night\n'
      ;;
    0330 | 03:30 | 0400 | 04:00 | deep-night | deepnight)
      printf '0400-deep-night\n'
      ;;
  esac
}

canonical_preset_name() {
  local preset="${1,,}"
  local mapped=""

  mapped="$(preset_alias "$preset")"
  if [[ -n "$mapped" ]]; then
    printf '%s\n' "$mapped"
  else
    printf '%s\n' "$preset"
  fi
}

state_namespace() {
  # Simplify: always use 'default' unless explicitly overridden by an environment variable.
  # This avoids mismatches when running from different contexts (systemd vs shell).
  printf 'default\n'
}

state_dir() {
  local state_home="${XDG_STATE_HOME:-$HOME/.local/state}"
  printf '%s/sunsetr/%s\n' "$state_home" "$(state_namespace)"
}

active_preset_path() {
  printf '%s/active_preset\n' "$(state_dir)"
}

dir_id_path() {
  printf '%s/dir_id\n' "$(state_dir)"
}

is_preset() {
  local preset
  preset="$(canonical_preset_name "$1")"
  [[ "$preset" == "default" ]] && return 0
  [[ -f "$CONFIG_ROOT/presets/$preset/sunsetr.toml" ]]
}

toml_get_value() {
  local cfg_file="$1"
  local key="$2"

  awk -v wanted="$key" '
    $0 ~ "^[[:space:]]*" wanted "[[:space:]]*=" {
      sub(/^[^=]*=[[:space:]]*/, "", $0)
      sub(/[[:space:]]*#.*/, "", $0)
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", $0)
      gsub(/^"|"$/, "", $0)
      print $0
      exit
    }
  ' "$cfg_file"
}

hhmm_sort_key() {
  local raw="${1//:/}"
  local hour minute

  [[ "$raw" =~ ^[0-9]{4}$ ]] || return 1
  hour="${raw:0:2}"
  minute="${raw:2:2}"

  (( 10#$hour <= 23 )) || return 1
  (( 10#$minute <= 59 )) || return 1

  printf '%d\n' "$(( (10#$hour * 100) + 10#$minute ))"
}

load_schedule() {
  local start preset hhmm last="" hhmm_key last_key=""

  SCHEDULE_STARTS=()
  SCHEDULE_START_KEYS=()
  SCHEDULE_PRESETS=()

  [[ -f "$SCHEDULE_FILE" ]] || die "schedule file not found: $SCHEDULE_FILE"

  while read -r start preset; do
    [[ -n "$start" && -n "$preset" ]] || continue

    hhmm="${start/:/}"
    hhmm_key="$(hhmm_sort_key "$start")" || die "invalid schedule time: $start"
    if [[ -n "$last_key" ]] && (( hhmm_key <= last_key )); then
      die "schedule must be strictly ascending: $start comes after ${last:0:2}:${last:2:2}"
    fi

    is_preset "$preset" || die "schedule references missing preset: $preset"
    SCHEDULE_STARTS+=("$start")
    SCHEDULE_START_KEYS+=("$hhmm_key")
    SCHEDULE_PRESETS+=("$preset")
    last="$hhmm"
    last_key="$hhmm_key"
  done < <(awk '
    /^[[:space:]]*#/ { next }
    NF >= 2 { print $1, $2 }
  ' "$SCHEDULE_FILE")

  [[ "${#SCHEDULE_PRESETS[@]}" -gt 0 ]] || die "schedule file is empty: $SCHEDULE_FILE"
}

select_auto_preset() {
  local now_hhmm="${1:-$(date +%H:%M)}"
  local now_key
  local selected=""
  local idx

  load_schedule
  now_key="$(hhmm_sort_key "$now_hhmm")" || die "invalid current time: $now_hhmm"
  selected="${SCHEDULE_PRESETS[$((${#SCHEDULE_PRESETS[@]} - 1))]}"

  for idx in "${!SCHEDULE_STARTS[@]}"; do
    if (( SCHEDULE_START_KEYS[idx] <= now_key )); then
      selected="${SCHEDULE_PRESETS[$idx]}"
    fi
  done

  printf '%s\n' "$selected"
}

write_directory_identity() {
  local dir
  dir="$(state_dir)"
  mkdir -p "$dir"
  stat -Lc '%i' "$CONFIG_ROOT" > "$(dir_id_path)"
}

clear_active_preset_state() {
  rm -f "$(active_preset_path)" "$(dir_id_path)"
}

get_active_preset_state() {
  local marker_path
  local preset

  marker_path="$(active_preset_path)"
  if [[ ! -f "$marker_path" ]]; then
    printf 'default\n'
    return 0
  fi

  preset="$(tr -d '[:space:]' < "$marker_path")"
  if [[ -z "$preset" || ! -f "$CONFIG_ROOT/presets/$preset/sunsetr.toml" ]]; then
    clear_active_preset_state
    printf 'default\n'
    return 0
  fi

  printf '%s\n' "$preset"
}

set_active_preset_state() {
  local preset="$1"

  [[ "$preset" != "default" ]] || {
    clear_active_preset_state
    return 0
  }

  is_preset "$preset" || die "preset not found: $preset"
  local s_dir
  s_dir="$(state_dir)"
  mkdir -p "$s_dir"
  write_directory_identity
  printf '%s\n' "$preset" > "$(active_preset_path)"
}

sunsetr_instance_running() {
  sunsetr status >/dev/null 2>&1
}

apply_runtime_preset() {
  local preset="$1"
  local active

  active="$(get_active_preset_state)"
  if [[ "$preset" == "$active" && "$preset" != "default" ]]; then
    set_active_preset_state "$preset"
    return 0
  fi

  set_active_preset_state "$preset"

  if [[ "$preset" == "default" ]]; then
    sunsetr preset default >/dev/null 2>&1 || {
      set_active_preset_state "$active"
      die "failed to switch sunsetr to default config"
    }
  else
    sunsetr preset "$preset" >/dev/null 2>&1 || {
      set_active_preset_state "$active"
      die "failed to switch sunsetr preset: $preset"
    }
  fi
}

sync_preset() {
  local preset="$1"
  local apply_now="$2"

  if [[ "$apply_now" -eq 1 ]] && sunsetr_instance_running; then
    apply_runtime_preset "$preset"
  else
    set_active_preset_state "$preset"
  fi
}

format_preset_label() {
  local preset="$1"
  if [[ "$preset" =~ ^([0-9]{2})([0-9]{2})-(.+)$ ]]; then
    printf '%s:%s %s\n' "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}" "${BASH_REMATCH[3]}"
  else
    printf '%s\n' "$preset"
  fi
}

show_status() {
  local scheduled active

  scheduled="$(select_auto_preset)"
  active="$(get_active_preset_state)"

  log "config root: $CONFIG_ROOT"
  log "schedule file: $SCHEDULE_FILE"
  log "scheduled preset: $scheduled"
  log "active preset state: $active"

  if sunsetr_instance_running; then
    sunsetr status
  else
    log "runtime: not running"
  fi
}

list_presets() {
  local idx next_idx start end preset cfg_file temp gamma

  load_schedule
  printf '%-14s %-22s %s\n' 'Range' 'Preset' 'Target'
  for idx in "${!SCHEDULE_PRESETS[@]}"; do
    next_idx=$(((idx + 1) % ${#SCHEDULE_PRESETS[@]}))
    start="${SCHEDULE_STARTS[$idx]}"
    end="${SCHEDULE_STARTS[$next_idx]}"
    preset="${SCHEDULE_PRESETS[$idx]}"
    cfg_file="$CONFIG_ROOT/presets/$preset/sunsetr.toml"
    temp="$(toml_get_value "$cfg_file" static_temp)"
    gamma="$(toml_get_value "$cfg_file" static_gamma)"
    printf '%-14s %-22s %sK @ %s%%\n' \
      "${start}-${end}" \
      "$(format_preset_label "$preset")" \
      "${temp:-?}" \
      "${gamma:-?}"
  done
}

main() {
  require_cmd sunsetr

  local args=()
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --apply)
        APPLY_AFTER_SET=1
        shift
        ;;
      --no-notify)
        NOTIFY_ENABLED=0
        shift
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        args+=("$1")
        shift
        ;;
    esac
  done

  [[ "${#args[@]}" -gt 0 ]] || {
    usage
    exit 2
  }

  local action="${args[0],,}"
  local legacy_profile="${args[1]:-}"
  local target

  if [[ -n "$legacy_profile" && "$legacy_profile" != "default" ]]; then
    warn "legacy profile argument '$legacy_profile' is ignored; sunsetr now uses native presets"
  fi

  case "$action" in
    list|-l|--list)
      list_presets
      ;;
    auto)
      target="$(select_auto_preset)"
      active="$(get_active_preset_state)"
      if [[ "$target" != "$active" ]]; then
        sync_preset "$target" "$APPLY_AFTER_SET"
        log "preset changed: $active -> $target"
        notify "sunsetr" "Profil degistirildi: $target"
      fi
      ;;
    apply)
      target="$(get_active_preset_state)"
      sync_preset "$target" 1
      log "active preset applied: $target"
      notify "sunsetr" "Aktif preset uygulandi: $target"
      ;;
    status|show)
      show_status
      ;;
    *)
      target="$(canonical_preset_name "$action")"
      is_preset "$target" || die "unknown command/preset: $action (use: $SCRIPT_NAME list)"
      sync_preset "$target" "$APPLY_AFTER_SET"
      log "preset selected: $target"
      notify "sunsetr" "Preset secildi: $target"
      ;;
  esac
}

main "$@"
