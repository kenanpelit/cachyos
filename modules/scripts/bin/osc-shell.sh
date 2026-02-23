#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# osc-shell
# -----------------------------------------------------------------------------
# Shell router for desktop IPC actions.
# - Provides a stable command surface for keybinds.
# - Routes actions to DMS or Noctalia based on profile/compositor.
# - Lets you switch shell backend on-demand without rewriting binds.
# -----------------------------------------------------------------------------

set -euo pipefail

SCRIPT_NAME="osc-shell"
PROFILE_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/osc-shell"
PROFILE_FILE="${PROFILE_DIR}/profile.conf"
CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/osc-shell"

DEFAULT_BACKEND_DEFAULT="dms"
DEFAULT_BACKEND_NIRI="noctalia"
DEFAULT_BACKEND_HYPRLAND="dms"

profile_default="$DEFAULT_BACKEND_DEFAULT"
profile_niri="$DEFAULT_BACKEND_NIRI"
profile_hyprland="$DEFAULT_BACKEND_HYPRLAND"

IPC_TARGET=""
IPC_METHOD=""
declare -a IPC_ARGS=()

trim() {
  local s="$*"
  s="${s#"${s%%[![:space:]]*}"}"
  s="${s%"${s##*[![:space:]]}"}"
  printf '%s' "$s"
}

to_lower() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]'
}

is_backend() {
  case "$1" in
    dms | noctalia) return 0 ;;
    *) return 1 ;;
  esac
}

notify_msg() {
  local title="$1"
  local body="$2"
  if command -v notify-send >/dev/null 2>&1; then
    notify-send "$title" "$body" >/dev/null 2>&1 || true
  fi
}

load_profile() {
  profile_default="$DEFAULT_BACKEND_DEFAULT"
  profile_niri="$DEFAULT_BACKEND_NIRI"
  profile_hyprland="$DEFAULT_BACKEND_HYPRLAND"

  [[ -f "$PROFILE_FILE" ]] || return 0

  local line key val
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="$(trim "$line")"
    [[ -z "$line" || "${line:0:1}" == "#" ]] && continue
    [[ "$line" == *=* ]] || continue

    key="$(to_lower "$(trim "${line%%=*}")")"
    val="$(to_lower "$(trim "${line#*=}")")"
    is_backend "$val" || continue

    case "$key" in
      default) profile_default="$val" ;;
      niri) profile_niri="$val" ;;
      hyprland) profile_hyprland="$val" ;;
    esac
  done <"$PROFILE_FILE"
}

save_profile() {
  mkdir -p "$PROFILE_DIR"
  cat >"$PROFILE_FILE" <<EOF
# ${SCRIPT_NAME} profile
default=${profile_default}
niri=${profile_niri}
hyprland=${profile_hyprland}
EOF
}

detect_compositor() {
  local all
  all="$(to_lower "${XDG_CURRENT_DESKTOP:-} ${XDG_SESSION_DESKTOP:-} ${DESKTOP_SESSION:-}")"

  if [[ "$all" == *"niri"* ]]; then
    printf 'niri\n'
    return 0
  fi
  if [[ "$all" == *"hypr"* ]]; then
    printf 'hyprland\n'
    return 0
  fi
  printf 'default\n'
}

backend_for_compositor() {
  local comp="$1"
  load_profile
  case "$comp" in
    niri) printf '%s\n' "$profile_niri" ;;
    hyprland) printf '%s\n' "$profile_hyprland" ;;
    *) printf '%s\n' "$profile_default" ;;
  esac
}

ensure_systemd_user() {
  command -v systemctl >/dev/null 2>&1 || return 1
  systemctl --user show-environment >/dev/null 2>&1
}

ensure_backend() {
  local backend="$1"

  case "$backend" in
    noctalia)
      if ensure_systemd_user; then
        systemctl --user stop dms.service >/dev/null 2>&1 || true
        systemctl --user stop dms-plugin-sync.service >/dev/null 2>&1 || true
        systemctl --user start noctalia.service >/dev/null 2>&1 || true
      fi
      ;;
    dms)
      if ensure_systemd_user; then
        systemctl --user stop noctalia.service >/dev/null 2>&1 || true
        systemctl --user start dms.service >/dev/null 2>&1 || true
      fi
      ;;
  esac
}

toggle_noctalia_bar_auto_hide() {
  local mode_file mode next
  mkdir -p "$CACHE_DIR"
  mode_file="${CACHE_DIR}/noctalia-bar-mode"

  mode="always_visible"
  if [[ -f "$mode_file" ]]; then
    mode="$(trim "$(cat "$mode_file" 2>/dev/null || echo always_visible)")"
  fi

  if [[ "$mode" == "auto_hide" ]]; then
    next="always_visible"
  else
    next="auto_hide"
  fi

  qs -c noctalia-shell ipc call bar setDisplayMode "$next" "all"
  printf '%s\n' "$next" >"$mode_file"
}

normalize_ipc() {
  local target="$1"
  local method="$2"
  shift 2 || true
  local -a args=("$@")

  case "${target}:${method}" in
    spotlight:toggle)
      target="launcher"; method="command"; args=()
      ;;
    spotlight:openQuery)
      target="launcher"; method="windows"; args=()
      ;;
    dash:toggle)
      if [[ "${args[0]:-}" == "overview" ]]; then
        target="launcher"; method="windows"; args=()
      else
        target="launcher"; method="toggle"; args=()
      fi
      ;;
    control-center:toggle)
      target="controlCenter"; method="toggle"; args=()
      ;;
    notifications:toggle)
      target="notifications"; method="toggleHistory"; args=()
      ;;
    processlist:focusOrToggle)
      target="systemMonitor"; method="toggle"; args=()
      ;;
    notepad:open)
      target="launcher"; method="command"; args=()
      ;;
    settings:focusOrToggle)
      target="settings"; method="toggle"; args=()
      ;;
    settings:openWith)
      if [[ "${args[0]:-}" == "keybinds" ]]; then
        target="plugin:keybind-cheatsheet"; method="toggle"; args=()
      fi
      ;;
    keybinds:toggle)
      target="plugin:keybind-cheatsheet"; method="toggle"; args=()
      ;;
    widget:toggle)
      if [[ "${args[0]:-}" == "sathiAi" ]]; then
        target="plugin:assistant-panel"; method="toggle"; args=()
      fi
      ;;
    powermenu:toggle)
      target="sessionMenu"; method="toggle"; args=()
      ;;
    inhibit:toggle)
      target="idleInhibitor"; method="toggle"; args=()
      ;;
    dankdash:wallpaper)
      target="wallpaper"; method="toggle"; args=()
      ;;
    theme:toggle)
      target="darkMode"; method="toggle"; args=()
      ;;
    night:toggle)
      target="nightLight"; method="toggle"; args=()
      ;;
    audio:increment)
      target="volume"; method="increase"; args=()
      ;;
    audio:decrement)
      target="volume"; method="decrease"; args=()
      ;;
    audio:mute)
      target="volume"; method="muteOutput"; args=()
      ;;
    audio:micmute)
      target="volume"; method="muteInput"; args=()
      ;;
    brightness:increment)
      target="brightness"; method="increase"; args=()
      ;;
    brightness:decrement)
      target="brightness"; method="decrease"; args=()
      ;;
    clipboard:toggle)
      target="plugin:clipper"; method="toggle"; args=()
      ;;
    niri:screenshot)
      target="plugin:screenshot"; method="takeScreenshot"; args=("region")
      ;;
    niri:screenshotScreen)
      target="plugin:screenshot"; method="takeScreenshot"; args=("output")
      ;;
    niri:screenshotWindow)
      target="plugin:screenshot"; method="takeScreenshot"; args=("window")
      ;;
  esac

  IPC_TARGET="$target"
  IPC_METHOD="$method"
  IPC_ARGS=("${args[@]}")
}

dms_ipc_call() {
  command -v dms >/dev/null 2>&1 || {
    echo "${SCRIPT_NAME}: dms command not found" >&2
    return 127
  }
  dms ipc call "$@"
}

power_profile_cycle() {
  command -v powerprofilesctl >/dev/null 2>&1 || return 1
  local current next
  current="$(powerprofilesctl get 2>/dev/null | tr '[:upper:]' '[:lower:]' || true)"
  case "$current" in
    power-saver | powersaver | power_saver) next="balanced" ;;
    balanced) next="performance" ;;
    performance) next="power-saver" ;;
    *) next="balanced" ;;
  esac
  powerprofilesctl set "$next"
}

route_dms_ipc() {
  local target="$1"
  local method="$2"
  shift 2 || true
  local -a args=("$@")

  case "${target}:${method}" in
    launcher:toggle) exec dms_ipc_call launcher toggle ;;
    launcher:command) exec dms_ipc_call spotlight toggle ;;
    launcher:windows) exec dms_ipc_call spotlight openQuery "!" ;;
    launcher:emoji) exec dms_ipc_call dash toggle overview ;;
    launcher:clipboard) exec dms_ipc_call clipboard toggle ;;
    launcher:settings) exec dms_ipc_call settings focusOrToggle ;;

    controlCenter:toggle) exec dms_ipc_call control-center toggle "" ;;

    settings:toggle | settings:open) exec dms_ipc_call settings focusOrToggle ;;
    settings:toggleTab | settings:openTab)
      if [[ "${args[0]:-}" == "keybinds" || "${args[0]:-}" == keybinds/* ]]; then
        exec dms_ipc_call settings openWith keybinds
      fi
      exec dms_ipc_call settings focusOrToggle
      ;;

    notifications:toggleHistory) exec dms_ipc_call notifications toggle ;;
    notifications:toggleDND) exec dms_ipc_call notifications toggle-dnd ;;
    notifications:dismissAll) exec dms_ipc_call notifications dismissAll ;;

    systemMonitor:toggle) exec dms_ipc_call processlist focusOrToggle ;;

    sessionMenu:toggle) exec dms_ipc_call powermenu toggle ;;
    sessionMenu:lock | lockScreen:lock) exec dms_ipc_call lock lock ;;
    sessionMenu:lockAndSuspend)
      dms_ipc_call lock lock >/dev/null 2>&1 || true
      exec systemctl suspend -i
      ;;

    plugin:clipper:toggle) exec dms_ipc_call clipboard toggle ;;
    plugin:keybind-cheatsheet:toggle) exec dms_ipc_call keybinds toggle niri ;;
    plugin:assistant-panel:toggle) exec dms_ipc_call widget toggle sathiAi ;;

    bar:toggle) exec dms_ipc_call bar toggle index 0 ;;
    bar:showBar) exec dms_ipc_call bar reveal index 0 ;;
    bar:hideBar) exec dms_ipc_call bar hide index 0 ;;
    bar:toggleAutoHide) exec dms_ipc_call bar toggleAutoHide index 0 ;;

    dock:toggle) exec dms_ipc_call dock toggle ;;

    wallpaper:toggle) exec dms_ipc_call dankdash wallpaper ;;
    wallpaper:random | wallpaper:next) exec dms_ipc_call wallpaper next ;;
    wallpaper:prev) exec dms_ipc_call wallpaper prev ;;

    darkMode:toggle) exec dms_ipc_call theme toggle ;;
    nightLight:toggle) exec dms_ipc_call night toggle ;;

    volume:increase) exec dms_ipc_call audio increment 5 ;;
    volume:decrease) exec dms_ipc_call audio decrement 5 ;;
    volume:muteOutput) exec dms_ipc_call audio mute ;;
    volume:muteInput) exec dms_ipc_call audio micmute ;;

    brightness:increase) exec dms_ipc_call brightness increment 5 "" ;;
    brightness:decrease) exec dms_ipc_call brightness decrement 5 "" ;;
    brightness:set)
      command -v brightnessctl >/dev/null 2>&1 || exit 1
      exec brightnessctl set "${args[0]:-50}%"
      ;;

    media:playPause) exec dms_ipc_call mpris playPause ;;
    media:next) exec dms_ipc_call mpris next ;;
    media:previous) exec dms_ipc_call mpris previous ;;
    media:pause) exec dms_ipc_call mpris pause ;;
    media:play) exec dms_ipc_call mpris play ;;
    media:stop) exec dms_ipc_call mpris stop ;;

    idleInhibitor:toggle) exec dms_ipc_call inhibit toggle ;;

    plugin:screenshot:takeScreenshot)
      case "${args[0]:-region}" in
        output | screen | fullscreen) exec dms_ipc_call niri screenshotScreen ;;
        window) exec dms_ipc_call niri screenshotWindow ;;
        *) exec dms_ipc_call niri screenshot ;;
      esac
      ;;

    powerProfile:cycle)
      exec power_profile_cycle
      ;;
    powerProfile:set)
      command -v powerprofilesctl >/dev/null 2>&1 || exit 1
      case "$(to_lower "${args[0]:-balanced}")" in
        powersaver | power_saver) exec powerprofilesctl set power-saver ;;
        *) exec powerprofilesctl set "${args[0]:-balanced}" ;;
      esac
      ;;

    wifi:toggle)
      command -v nmcli >/dev/null 2>&1 || exit 1
      if [[ "$(nmcli radio wifi 2>/dev/null | tr '[:upper:]' '[:lower:]')" == "enabled" ]]; then
        exec nmcli radio wifi off
      fi
      exec nmcli radio wifi on
      ;;
    wifi:enable)
      command -v nmcli >/dev/null 2>&1 || exit 1
      exec nmcli radio wifi on
      ;;
    wifi:disable)
      command -v nmcli >/dev/null 2>&1 || exit 1
      exec nmcli radio wifi off
      ;;

    bluetooth:toggle)
      command -v bluetooth_toggle >/dev/null 2>&1 || exit 1
      exec bluetooth_toggle
      ;;
  esac

  exec dms_ipc_call "$target" "$method" "${args[@]}"
}

route_noctalia_ipc() {
  local target="$1"
  local method="$2"
  shift 2 || true
  local -a args=("$@")

  case "${target}:${method}" in
    wallpaper:next | wallpaper:prev)
      target="wallpaper"; method="random"; args=()
      ;;
    bar:toggleAutoHide)
      toggle_noctalia_bar_auto_hide
      return 0
      ;;
  esac

  if ! command -v qs >/dev/null 2>&1; then
    echo "${SCRIPT_NAME}: qs command not found" >&2
    return 127
  fi

  if ! qs -c noctalia-shell ipc call "$target" "$method" "${args[@]}" >/dev/null 2>&1; then
    ensure_backend noctalia
  fi

  qs -c noctalia-shell ipc call "$target" "$method" "${args[@]}"
}

cmd_backend() {
  local comp="${1:-$(detect_compositor)}"
  comp="$(to_lower "$comp")"
  backend_for_compositor "$comp"
}

cmd_profile() {
  local sub="${1:-show}"
  shift || true
  load_profile

  case "$sub" in
    show)
      cat <<EOF
default=${profile_default}
niri=${profile_niri}
hyprland=${profile_hyprland}
active_compositor=$(detect_compositor)
active_backend=$(backend_for_compositor "$(detect_compositor)")
EOF
      ;;
    set)
      local key="${1:-}" backend="${2:-}"
      key="$(to_lower "$key")"
      backend="$(to_lower "$backend")"
      [[ -n "$key" && -n "$backend" ]] || {
        echo "Usage: ${SCRIPT_NAME} profile set <default|niri|hyprland> <dms|noctalia>" >&2
        return 1
      }
      is_backend "$backend" || {
        echo "Invalid backend: $backend" >&2
        return 1
      }
      case "$key" in
        default) profile_default="$backend" ;;
        niri) profile_niri="$backend" ;;
        hyprland) profile_hyprland="$backend" ;;
        *)
          echo "Invalid profile key: $key" >&2
          return 1
          ;;
      esac
      save_profile
      ;;
    use)
      local backend="${1:-}" comp="${2:-$(detect_compositor)}"
      backend="$(to_lower "$backend")"
      comp="$(to_lower "$comp")"
      is_backend "$backend" || {
        echo "Usage: ${SCRIPT_NAME} profile use <dms|noctalia> [niri|hyprland|default]" >&2
        return 1
      }
      case "$comp" in
        niri | hyprland | default)
          "$0" profile set "$comp" "$backend"
          ;;
        *)
          echo "Invalid compositor key: $comp" >&2
          return 1
          ;;
      esac
      ;;
    *)
      echo "Usage: ${SCRIPT_NAME} profile <show|set|use>" >&2
      return 1
      ;;
  esac
}

cmd_switch() {
  local backend="${1:-}" comp="${2:-$(detect_compositor)}"
  backend="$(to_lower "$backend")"
  comp="$(to_lower "$comp")"
  is_backend "$backend" || {
    echo "Usage: ${SCRIPT_NAME} switch <dms|noctalia> [niri|hyprland|default]" >&2
    return 1
  }
  case "$comp" in
    niri | hyprland | default) ;;
    *)
      echo "Invalid compositor key: $comp" >&2
      return 1
      ;;
  esac

  "$0" profile set "$comp" "$backend"
  ensure_backend "$backend"
  notify_msg "Shell Backend" "${comp}: ${backend}"
  printf '%s\n' "$backend"
}

cmd_ensure() {
  local backend="${1:-$(backend_for_compositor "$(detect_compositor)")}"
  backend="$(to_lower "$backend")"
  is_backend "$backend" || {
    echo "Invalid backend: $backend" >&2
    return 1
  }
  ensure_backend "$backend"
}

cmd_ipc() {
  local sub="${1:-}"
  shift || true

  local backend
  backend="$(backend_for_compositor "$(detect_compositor)")"

  case "$sub" in
    show)
      if [[ "$backend" == "noctalia" ]]; then
        exec qs -c noctalia-shell ipc show
      fi
      echo "${SCRIPT_NAME}: ipc show is only supported for noctalia backend" >&2
      return 1
      ;;
    call)
      local target="${1:-}" method="${2:-}"
      shift 2 || true
      [[ -n "$target" && -n "$method" ]] || {
        echo "Usage: ${SCRIPT_NAME} ipc call <target> <method> [args...]" >&2
        return 1
      }
      normalize_ipc "$target" "$method" "$@"
      if [[ "$backend" == "noctalia" ]]; then
        exec route_noctalia_ipc "$IPC_TARGET" "$IPC_METHOD" "${IPC_ARGS[@]}"
      fi
      exec route_dms_ipc "$IPC_TARGET" "$IPC_METHOD" "${IPC_ARGS[@]}"
      ;;
    *)
      echo "Usage: ${SCRIPT_NAME} ipc <show|call>" >&2
      return 1
      ;;
  esac
}

usage() {
  cat <<EOF
Usage:
  ${SCRIPT_NAME} backend [compositor]
  ${SCRIPT_NAME} profile show
  ${SCRIPT_NAME} profile set <default|niri|hyprland> <dms|noctalia>
  ${SCRIPT_NAME} profile use <dms|noctalia> [niri|hyprland|default]
  ${SCRIPT_NAME} switch <dms|noctalia> [niri|hyprland|default]
  ${SCRIPT_NAME} ensure [dms|noctalia]
  ${SCRIPT_NAME} ipc show
  ${SCRIPT_NAME} ipc call <target> <method> [args...]

Examples:
  ${SCRIPT_NAME} profile show
  ${SCRIPT_NAME} switch noctalia niri
  ${SCRIPT_NAME} ipc call launcher toggle
  ${SCRIPT_NAME} ipc call plugin:clipper toggle
EOF
}

main() {
  local cmd="${1:-help}"
  shift || true

  case "$cmd" in
    backend) cmd_backend "$@" ;;
    profile) cmd_profile "$@" ;;
    switch) cmd_switch "$@" ;;
    ensure) cmd_ensure "$@" ;;
    ipc) cmd_ipc "$@" ;;
    help | --help | -h) usage ;;
    *)
      usage
      return 1
      ;;
  esac
}

main "$@"
