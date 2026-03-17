#!/usr/bin/env bash
# ==============================================================================
# Script: sunsetr-set.sh
# Description: Profile-aware helper for sunsetr to manage display color temperature
# Usage: sunsetr-set.sh [list|apply|status|<preset>] [profile] [options]
# ==============================================================================
set -euo pipefail

# -----------------------------------------------------------------------------
# sunsetr-set
# -----------------------------------------------------------------------------
# Profile-aware helper for sunsetr:
# - write preset values to a target profile
# - optionally apply that profile immediately
# - stay compatible with legacy usage:
#     sunsetr-set <preset> [profile]
#     sunsetr-set apply [profile]
# -----------------------------------------------------------------------------

SCRIPT_NAME="$(basename "$0")"
CONFIG_ROOT="${XDG_CONFIG_HOME:-$HOME/.config}/sunsetr"
DEFAULT_PROFILE="default"
DEFAULT_LATITUDE="${SUNSETR_LATITUDE:-41.0082}"
DEFAULT_LONGITUDE="${SUNSETR_LONGITUDE:-28.9784}"
NOTIFY_ENABLED=1
APPLY_AFTER_SET=0

usage() {
  cat <<EOF
$SCRIPT_NAME - Sunsetr profile helper

Usage:
  $SCRIPT_NAME list
  $SCRIPT_NAME auto [profile]
  $SCRIPT_NAME <preset> [profile]
  $SCRIPT_NAME apply [profile]
  $SCRIPT_NAME status [profile]

Options:
  --apply                 Apply profile immediately after preset write
  --lat <value>           Latitude override (default: preset value)
  --lon <value>           Longitude override (default: preset value)
  --no-notify             Disable desktop notifications
  -h, --help              Show help

Presets:
  Values are read dynamically from:
  $CONFIG_ROOT/presets/*/sunsetr.toml

Examples:
  $SCRIPT_NAME auto --apply
  $SCRIPT_NAME 2030-dusk
  $SCRIPT_NAME dusk work
  $SCRIPT_NAME 2330-night --apply
  $SCRIPT_NAME apply work
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

ensure_runtime_dir() {
  if [[ -z "${XDG_RUNTIME_DIR:-}" && -d "/run/user/$(id -u)" ]]; then
    export XDG_RUNTIME_DIR="/run/user/$(id -u)"
  fi
}

is_preset() {
  local preset
  preset="$(canonical_preset_name "$1")"
  [[ -f "$CONFIG_ROOT/presets/$preset/sunsetr.toml" ]]
}

scheduled_presets() {
  local preset_root="$CONFIG_ROOT/presets"
  local dir preset

  [[ -d "$preset_root" ]] || return 0

  while IFS= read -r -d '' dir; do
    preset="$(basename "$dir")"
    [[ "$preset" =~ ^[0-9]{4}- ]] || continue
    [[ -f "$dir/sunsetr.toml" ]] || continue
    printf '%s\n' "$preset"
  done < <(find "$preset_root" -mindepth 1 -maxdepth 1 -type d -print0 | sort -z)
}

select_auto_preset() {
  local now_hhmm="${1:-$(date +%H%M)}"
  local preset anchor selected="" last=""

  while IFS= read -r preset; do
    [[ "$preset" =~ ^([0-9]{4})- ]] || continue
    anchor="${BASH_REMATCH[1]}"
    last="$preset"
    if [[ "$anchor" -le "$now_hhmm" ]]; then
      selected="$preset"
    fi
  done < <(scheduled_presets)

  if [[ -n "$selected" ]]; then
    printf '%s\n' "$selected"
    return 0
  fi

  [[ -n "$last" ]] || die "no scheduled presets found in $CONFIG_ROOT/presets"
  printf '%s\n' "$last"
}

preset_alias() {
  case "${1,,}" in
    0730 | 07:30 | morning)
      printf '0730-morning\n'
      ;;
    1830 | 18:30 | sunset)
      printf '1830-sunset\n'
      ;;
    2030 | 20:30 | dusk)
      printf '2030-dusk\n'
      ;;
    2200 | 22:00 | evening)
      printf '2200-evening\n'
      ;;
    2330 | 23:30 | night)
      printf '2330-night\n'
      ;;
    0130 | 01:30 | late-night | latenight)
      printf '0130-late-night\n'
      ;;
    0330 | 03:30 | deep-night | deepnight)
      printf '0330-deep-night\n'
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

format_preset_label() {
  local preset="$1"
  if [[ "$preset" =~ ^([0-9]{2})([0-9]{2})-(.+)$ ]]; then
    local hh="${BASH_REMATCH[1]}"
    local mm="${BASH_REMATCH[2]}"
    local name="${BASH_REMATCH[3]}"
    printf '%s %s\n' "${hh}:${mm}" "$name"
  else
    printf '%s\n' "$preset"
  fi
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

print_preset_line() {
  local preset="$1"
  local cfg_file="$CONFIG_ROOT/presets/$preset/sunsetr.toml"
  local day_temp night_temp day_gamma night_gamma label

  if [[ ! -f "$cfg_file" ]]; then
    printf '  %-14s (missing: sunsetr.toml)\n' "$preset"
    return
  fi

  day_temp="$(toml_get_value "$cfg_file" day_temp)"
  night_temp="$(toml_get_value "$cfg_file" night_temp)"
  day_gamma="$(toml_get_value "$cfg_file" day_gamma)"
  night_gamma="$(toml_get_value "$cfg_file" night_gamma)"
  label="$(format_preset_label "$preset")"

  if [[ -z "$day_temp" || -z "$night_temp" || -z "$day_gamma" || -z "$night_gamma" ]]; then
    printf '  %-20s (invalid preset values)\n' "$label"
    return
  fi

  if [[ "$day_temp" == "$night_temp" && "$day_gamma" == "$night_gamma" ]]; then
    printf '  %-20s (%sK, %s%%)\n' "$label" "$day_temp" "$day_gamma"
  else
    printf '  %-20s (%s/%sK, %s/%s)\n' "$label" "$day_temp" "$night_temp" "$day_gamma" "$night_gamma"
  fi
}

list_presets() {
  local preset_root="$CONFIG_ROOT/presets"
  local preset
  local -a detected=()
  local -a preferred=(
    0730-morning
    1830-sunset
    2030-dusk
    2200-evening
    2330-night
    0130-late-night
    0330-deep-night
  )
  local -A seen=()

  echo "Presetler:"

  if [[ ! -d "$preset_root" ]]; then
    echo "  (preset dizini yok: $preset_root)"
    return 0
  fi

  while IFS= read -r -d '' dir; do
    if [[ -f "$dir/sunsetr.toml" ]]; then
      detected+=("$(basename "$dir")")
    fi
  done < <(find "$preset_root" -mindepth 1 -maxdepth 1 -type d -print0 | sort -z)

  if [[ "${#detected[@]}" -eq 0 ]]; then
    echo "  (preset bulunamadı)"
    return 0
  fi

  for preset in "${preferred[@]}"; do
    local found=0
    local candidate
    for candidate in "${detected[@]}"; do
      if [[ "$candidate" == "$preset" ]]; then
        print_preset_line "$preset"
        seen["$preset"]=1
        found=1
        break
      fi
    done
    [[ "$found" -eq 1 ]] || true
  done

  for preset in "${detected[@]}"; do
    [[ -n "${seen[$preset]:-}" ]] && continue
    print_preset_line "$preset"
  done
}

validate_profile() {
  local profile="$1"
  [[ "$profile" =~ ^[A-Za-z0-9._-]+$ ]] || {
    die "invalid profile name: $profile"
  }
}

profile_to_dir() {
  local profile="$1"
  if [[ "$profile" == "$DEFAULT_PROFILE" ]]; then
    printf '%s\n' "$CONFIG_ROOT"
  else
    printf '%s\n' "$CONFIG_ROOT/presets/$profile"
  fi
}

ensure_config_dir() {
  local cfg_dir="$1"
  local cfg_file="$cfg_dir/sunsetr.toml"

  mkdir -p "$cfg_dir"
  if [[ ! -f "$cfg_file" && -f "$CONFIG_ROOT/sunsetr.toml" ]]; then
    cp -f "$CONFIG_ROOT/sunsetr.toml" "$cfg_file"
  fi
}

require_existing_config() {
  local profile="$1"
  local cfg_dir="$2"
  local cfg_file="$cfg_dir/sunsetr.toml"

  if [[ -f "$cfg_file" ]]; then
    return 0
  fi

  if is_preset "$profile"; then
    die "apply/status expects a profile, not preset: $profile (use: $SCRIPT_NAME $profile --apply)"
  fi

  die "profile not found: $profile ($cfg_file)"
}

apply_preset() {
  local preset
  preset="$(canonical_preset_name "$1")"
  local profile="$2"
  local latitude="$3"
  local longitude="$4"
  local target="default"
  local -a keys=(
    backend
    transition_mode
    smoothing
    startup_duration
    shutdown_duration
    adaptive_interval
    day_temp
    night_temp
    day_gamma
    night_gamma
    update_interval
    static_temp
    static_gamma
    sunset
    sunrise
    transition_duration
    latitude
    longitude
  )
  local -a set_args=()
  local key value
  local preset_cfg_file

  if [[ "$profile" != "$DEFAULT_PROFILE" ]]; then
    target="$profile"
  fi

  preset_cfg_file="$CONFIG_ROOT/presets/$preset/sunsetr.toml"
  [[ -f "$preset_cfg_file" ]] || die "preset not found: $preset ($preset_cfg_file)"

  for key in "${keys[@]}"; do
    value="$(toml_get_value "$preset_cfg_file" "$key")"
    if [[ -n "$value" ]]; then
      set_args+=("${key}=${value}")
    fi
  done

  if [[ -n "$latitude" ]]; then
    set_args+=("latitude=${latitude}")
  elif ! printf '%s\n' "${set_args[@]}" | grep -q '^latitude='; then
    set_args+=("latitude=${DEFAULT_LATITUDE}")
  fi

  if [[ -n "$longitude" ]]; then
    set_args+=("longitude=${longitude}")
  elif ! printf '%s\n' "${set_args[@]}" | grep -q '^longitude='; then
    set_args+=("longitude=${DEFAULT_LONGITUDE}")
  fi

  # Force explicit target to avoid interactive prompt based on active preset.
  sunsetr --config "$CONFIG_ROOT" set --target "$target" "${set_args[@]}"
}

systemd_user_ready() {
  command -v systemctl >/dev/null 2>&1 || return 1
  systemctl --user show-environment >/dev/null 2>&1
}

sunsetr_service_installed() {
  systemd_user_ready || return 1
  systemctl --user cat sunsetr.service >/dev/null 2>&1
}

activate_profile() {
  local profile="$1"
  local cfg_dir="$2"

  if [[ "$profile" == "$DEFAULT_PROFILE" ]] && sunsetr_service_installed; then
    if systemctl --user restart sunsetr.service >/dev/null 2>&1; then
      log "profile applied via sunsetr.service restart: $profile"
      notify "sunsetr" "Profil uygulandı: $profile"
      return 0
    fi
  fi

  if systemd_user_ready && systemctl --user status sunsetr.service >/dev/null 2>&1; then
    systemctl --user stop sunsetr.service >/dev/null 2>&1 || true
  fi

  sunsetr stop >/dev/null 2>&1 || true
  sunsetr --background --config "$cfg_dir"

  log "profile applied via standalone process: $profile"
  notify "sunsetr" "Profil uygulandı: $profile"
}

show_status() {
  local profile="$1"
  local cfg_dir="$2"

  log "profile: $profile"
  log "config: $cfg_dir/sunsetr.toml"
  sunsetr --config "$cfg_dir" get backend transition_mode day_temp night_temp day_gamma night_gamma static_temp static_gamma sunset sunrise transition_duration latitude longitude
}

main() {
  require_cmd sunsetr
  ensure_runtime_dir

  local latitude=""
  local longitude=""
  local args=()

  while [[ $# -gt 0 ]]; do
    case "$1" in
    --apply)
      APPLY_AFTER_SET=1
      shift
      ;;
    --lat)
      [[ $# -ge 2 ]] || die "--lat requires a value"
      latitude="$2"
      shift 2
      ;;
    --lon)
      [[ $# -ge 2 ]] || die "--lon requires a value"
      longitude="$2"
      shift 2
      ;;
    --no-notify)
      NOTIFY_ENABLED=0
      shift
      ;;
    -h | --help)
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
  action="$(canonical_preset_name "$action")"
  local profile="$DEFAULT_PROFILE"
  local cfg_dir

  case "$action" in
  list | -l | --list)
    list_presets
    exit 0
    ;;
  auto)
    profile="${args[1]:-$DEFAULT_PROFILE}"
    validate_profile "$profile"
    cfg_dir="$(profile_to_dir "$profile")"

    action="$(select_auto_preset)"
    ensure_config_dir "$cfg_dir"
    apply_preset "$action" "$profile" "$latitude" "$longitude"

    log "auto preset selected: $action -> $profile"
    notify "sunsetr" "Otomatik preset: $action -> $profile"

    if [[ "$APPLY_AFTER_SET" -eq 1 ]]; then
      activate_profile "$profile" "$cfg_dir"
    fi
    ;;
  apply)
    profile="${args[1]:-$DEFAULT_PROFILE}"
    validate_profile "$profile"
    cfg_dir="$(profile_to_dir "$profile")"
    require_existing_config "$profile" "$cfg_dir"
    activate_profile "$profile" "$cfg_dir"
    ;;
  status | show)
    profile="${args[1]:-$DEFAULT_PROFILE}"
    validate_profile "$profile"
    cfg_dir="$(profile_to_dir "$profile")"
    require_existing_config "$profile" "$cfg_dir"
    show_status "$profile" "$cfg_dir"
    ;;
  *)
    if ! is_preset "$action"; then
      die "unknown command/preset: $action (use: $SCRIPT_NAME list)"
    fi

    profile="${args[1]:-$DEFAULT_PROFILE}"
    validate_profile "$profile"
    cfg_dir="$(profile_to_dir "$profile")"

    ensure_config_dir "$cfg_dir"
    apply_preset "$action" "$profile" "$latitude" "$longitude"

    log "preset written: $action -> $profile"
    notify "sunsetr" "Preset yazıldı: $action -> $profile"

    if [[ "$APPLY_AFTER_SET" -eq 1 ]]; then
      activate_profile "$profile" "$cfg_dir"
    fi
    ;;
  esac
}

main "$@"
