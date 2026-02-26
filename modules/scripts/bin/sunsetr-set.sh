#!/usr/bin/env bash
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
  $SCRIPT_NAME night
  $SCRIPT_NAME warm work
  $SCRIPT_NAME best --apply
  $SCRIPT_NAME apply night
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
  local preset="${1,,}"
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

print_preset_line() {
  local preset="$1"
  local cfg_file="$CONFIG_ROOT/presets/$preset/sunsetr.toml"
  local day_temp night_temp day_gamma night_gamma

  if [[ ! -f "$cfg_file" ]]; then
    printf '  %-14s (missing: sunsetr.toml)\n' "$preset"
    return
  fi

  day_temp="$(toml_get_value "$cfg_file" day_temp)"
  night_temp="$(toml_get_value "$cfg_file" night_temp)"
  day_gamma="$(toml_get_value "$cfg_file" day_gamma)"
  night_gamma="$(toml_get_value "$cfg_file" night_gamma)"

  if [[ -z "$day_temp" || -z "$night_temp" || -z "$day_gamma" || -z "$night_gamma" ]]; then
    printf '  %-14s (invalid preset values)\n' "$preset"
    return
  fi

  printf '  %-14s (%s/%sK, %s/%s)\n' "$preset" "$day_temp" "$night_temp" "$day_gamma" "$night_gamma"
}

list_presets() {
  local preset_root="$CONFIG_ROOT/presets"
  local preset
  local -a detected=()
  local -a preferred=(day night warm dim focus best cinema dms)
  local -A seen=()

  echo "Presetler:"

  if [[ ! -d "$preset_root" ]]; then
    echo "  (preset dizini yok: $preset_root)"
    return 0
  fi

  while IFS= read -r -d '' dir; do
    detected+=("$(basename "$dir")")
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

apply_preset() {
  local preset="${1,,}"
  local profile="$2"
  local latitude="$3"
  local longitude="$4"
  local day_temp night_temp day_gamma night_gamma
  local preset_cfg_file
  local target="default"

  if [[ "$profile" != "$DEFAULT_PROFILE" ]]; then
    target="$profile"
  fi

  preset_cfg_file="$CONFIG_ROOT/presets/$preset/sunsetr.toml"
  [[ -f "$preset_cfg_file" ]] || die "preset not found: $preset ($preset_cfg_file)"

  day_temp="$(toml_get_value "$preset_cfg_file" day_temp)"
  night_temp="$(toml_get_value "$preset_cfg_file" night_temp)"
  day_gamma="$(toml_get_value "$preset_cfg_file" day_gamma)"
  night_gamma="$(toml_get_value "$preset_cfg_file" night_gamma)"

  [[ -n "$day_temp" ]] || die "preset '$preset' missing: day_temp"
  [[ -n "$night_temp" ]] || die "preset '$preset' missing: night_temp"
  [[ -n "$day_gamma" ]] || die "preset '$preset' missing: day_gamma"
  [[ -n "$night_gamma" ]] || die "preset '$preset' missing: night_gamma"

  if [[ -z "$latitude" ]]; then
    latitude="$(toml_get_value "$preset_cfg_file" latitude)"
  fi
  if [[ -z "$longitude" ]]; then
    longitude="$(toml_get_value "$preset_cfg_file" longitude)"
  fi

  [[ -n "$latitude" ]] || latitude="$DEFAULT_LATITUDE"
  [[ -n "$longitude" ]] || longitude="$DEFAULT_LONGITUDE"

  # Force explicit target to avoid interactive prompt based on active preset.
  sunsetr --config "$CONFIG_ROOT" set --target "$target" \
    day_temp="$day_temp" \
    night_temp="$night_temp" \
    day_gamma="$day_gamma" \
    night_gamma="$night_gamma" \
    latitude="$latitude" \
    longitude="$longitude"
}

systemd_user_ready() {
  command -v systemctl >/dev/null 2>&1 || return 1
  systemctl --user show-environment >/dev/null 2>&1
}

activate_profile() {
  local profile="$1"
  local cfg_dir="$2"

  if [[ "$profile" == "$DEFAULT_PROFILE" ]] && systemd_user_ready; then
    if systemctl --user status sunsetr.service >/dev/null 2>&1; then
      systemctl --user restart sunsetr.service >/dev/null 2>&1 || true
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
  sunsetr --config "$cfg_dir" get day_temp night_temp day_gamma night_gamma latitude longitude
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
  local profile="$DEFAULT_PROFILE"
  local cfg_dir

  case "$action" in
  list | -l | --list)
    list_presets
    exit 0
    ;;
  apply)
    profile="${args[1]:-$DEFAULT_PROFILE}"
    validate_profile "$profile"
    cfg_dir="$(profile_to_dir "$profile")"
    ensure_config_dir "$cfg_dir"
    activate_profile "$profile" "$cfg_dir"
    ;;
  status | show)
    profile="${args[1]:-$DEFAULT_PROFILE}"
    validate_profile "$profile"
    cfg_dir="$(profile_to_dir "$profile")"
    ensure_config_dir "$cfg_dir"
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
