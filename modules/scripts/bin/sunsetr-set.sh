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
  --lat <value>           Latitude override (default: $DEFAULT_LATITUDE)
  --lon <value>           Longitude override (default: $DEFAULT_LONGITUDE)
  --no-notify             Disable desktop notifications
  -h, --help              Show help

Presets:
  day, night, warm, dim, focus, best, cinema

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
  case "${1,,}" in
  day | night | warm | dim | focus | best | cinema) return 0 ;;
  *) return 1 ;;
  esac
}

list_presets() {
  cat <<'EOF'
Presetler:
  day     (4500/4000K, 100/95)
  night   (3500/3300K, 90/85)
  warm    (4200/3200K, 100/90)
  dim     (3500/3000K, 90/80)
  focus   (5000/4500K, 100/95)
  best    (3500/3300K, 90/85)
  cinema  (3800/2700K, 95/85)
EOF
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
    printf '%s\n' "$CONFIG_ROOT/profiles/$profile"
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
  local cfg_dir="$2"
  local latitude="$3"
  local longitude="$4"
  local day_temp night_temp day_gamma night_gamma

  case "$preset" in
  day)
    day_temp=4500; night_temp=4000; day_gamma=100; night_gamma=95
    ;;
  night)
    day_temp=3500; night_temp=3300; day_gamma=90; night_gamma=85
    ;;
  warm)
    day_temp=4200; night_temp=3200; day_gamma=100; night_gamma=90
    ;;
  dim)
    day_temp=3500; night_temp=3000; day_gamma=90; night_gamma=80
    ;;
  focus)
    day_temp=5000; night_temp=4500; day_gamma=100; night_gamma=95
    ;;
  best)
    day_temp=3500; night_temp=3300; day_gamma=90; night_gamma=85
    ;;
  cinema)
    day_temp=3800; night_temp=2700; day_gamma=95; night_gamma=85
    ;;
  *)
    die "unknown preset: $preset"
    ;;
  esac

  sunsetr --config "$cfg_dir" set \
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

  local latitude="$DEFAULT_LATITUDE"
  local longitude="$DEFAULT_LONGITUDE"
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
    apply_preset "$action" "$cfg_dir" "$latitude" "$longitude"

    log "preset written: $action -> $profile"
    notify "sunsetr" "Preset yazıldı: $action -> $profile"

    if [[ "$APPLY_AFTER_SET" -eq 1 ]]; then
      activate_profile "$profile" "$cfg_dir"
    fi
    ;;
  esac
}

main "$@"
