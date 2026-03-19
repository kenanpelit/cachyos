#!/usr/bin/env bash
# Dedicated monitor/workspace routing helper for Hyprland session bootstrap.

set -euo pipefail

DEFAULT_WORKSPACE="2"
SLEEP_DURATION="0.2"
PRIMARY_MONITOR="eDP-1"
NOTIFY_ENABLED=true
NOTIFY_TIMEOUT=3000

BOLD="\e[1m"
RED="\e[31m"
GREEN="\e[32m"
YELLOW="\e[33m"
BLUE="\e[34m"
RESET="\e[0m"

fatal() {
  echo -e "${RED}x${RESET} $*" >&2
  exit 1
}

info() { echo -e "${BLUE}>${RESET} $*"; }
ok() { echo -e "${GREEN}+${RESET} $*"; }

send_notification() {
  $NOTIFY_ENABLED || return 0

  local title="$1" msg="$2" urgency="${3:-normal}" icon="${4:-video-display}"
  if command -v dunstify >/dev/null 2>&1; then
    dunstify -t "$NOTIFY_TIMEOUT" -u "$urgency" -i "$icon" "$title" "$msg"
  elif command -v notify-send >/dev/null 2>&1; then
    notify-send -t "$NOTIFY_TIMEOUT" -u "$urgency" -i "$icon" "$title" "$msg"
  else
    local color="rgb(61afef)"
    [[ "$urgency" == "critical" ]] && color="rgb(e06c75)"
    hyprctl notify -1 "$NOTIFY_TIMEOUT" "$color" "$title: $msg" >/dev/null 2>&1 || true
  fi
}

check_hyprland() {
  command -v hyprctl >/dev/null 2>&1 || fatal "Hyprland (hyprctl) not found."
  hyprctl version >/dev/null 2>&1 || fatal "Cannot connect to Hyprland socket."
}

list_monitors() {
  info "Available monitors:"
  if command -v jq >/dev/null 2>&1; then
    hyprctl monitors -j | jq -r '
      .[] |
      (
        "  " +
        .name + "\t(" +
        (.width|tostring) + "x" + (.height|tostring) +
        " @ " + (.refreshRate|tostring) + "Hz)\t" +
        (if .focused then "ACTIVE" else "" end)
      )'
  else
    hyprctl monitors | grep "^Monitor"
  fi
}

find_external_monitor() {
  if command -v jq >/dev/null 2>&1; then
    hyprctl monitors -j | jq -r ".[] | select(.name != \"$PRIMARY_MONITOR\") | .name" | head -1
  else
    hyprctl monitors | grep "^Monitor" | grep -v "$PRIMARY_MONITOR" | awk '{print $2}' | head -1
  fi
}

get_active_monitor() {
  if command -v jq >/dev/null 2>&1; then
    hyprctl monitors -j | jq -r '.[] | select(.focused == true) | .name'
  else
    hyprctl monitors | awk '/focused: yes/{getline prev; print prev}' | awk '{print $2}'
  fi
}

get_monitor_info() {
  local mon="$1"
  if command -v jq >/dev/null 2>&1; then
    hyprctl monitors -j | jq -r ".[] | select(.name==\"$mon\") | \"\(.width)x\(.height)@\(.refreshRate)Hz\""
  else
    hyprctl monitors | grep -A1 "Monitor $mon" | grep -Eo '[0-9]+x[0-9]+'
  fi
}

validate_monitor() {
  local mon="$1"
  if command -v jq >/dev/null 2>&1; then
    hyprctl monitors -j | jq -e ".[] | select(.name==\"$mon\")" >/dev/null 2>&1
  else
    hyprctl monitors | grep -q "^Monitor $mon"
  fi
}

validate_workspace() {
  [[ "$1" =~ ^[0-9]+$ && "$1" -ge 1 && "$1" -le 10 ]] || fatal "Workspace must be between 1 and 10."
}

run_hyprctl() {
  local cmd="$1" desc="$2"
  info "$desc"
  hyprctl dispatch "$cmd" >/dev/null 2>&1 || fatal "$desc failed."
}

show_help() {
  cat <<EOF
${BOLD}hypr-session-route${RESET} - smart monitor and workspace router for Hyprland

Usage:
  hypr-session-route [OPTIONS] [WORKSPACE]

Options:
  -h, --help           Show this help message
  -l, --list           List current monitors and workspaces
  -t, --timeout NUM    Delay between monitor switch (default: $SLEEP_DURATION)
  -m, --monitor NAME   Manually specify monitor
  -n, --no-notify      Disable notifications
  -p, --primary        Force switch to primary monitor only
EOF
}

main() {
  local monitor="" workspace="$DEFAULT_WORKSPACE" primary_only=false manual_monitor=false

  while (($#)); do
    case "$1" in
      -h|--help)
        show_help
        exit 0
        ;;
      -l|--list)
        check_hyprland
        list_monitors
        hyprctl workspaces | grep workspace
        exit 0
        ;;
      -t|--timeout)
        [[ "${2:-}" =~ ^[0-9]+(\.[0-9]+)?$ ]] || fatal "--timeout expects a number"
        SLEEP_DURATION="$2"
        shift 2
        ;;
      -m|--monitor)
        monitor="${2:-}"
        [[ -n "$monitor" ]] || fatal "--monitor requires a name"
        manual_monitor=true
        shift 2
        ;;
      -n|--no-notify)
        NOTIFY_ENABLED=false
        shift
        ;;
      -p|--primary)
        primary_only=true
        shift
        ;;
      -*)
        fatal "Unknown option: $1"
        ;;
      *)
        workspace="$1"
        shift
        ;;
    esac
  done

  check_hyprland
  validate_workspace "$workspace"

  if $primary_only; then
    monitor="$PRIMARY_MONITOR"
    send_notification "Monitor Switch" "Returning to primary monitor ($monitor)"
  elif ! $manual_monitor; then
    info "Detecting external monitor..."
    monitor="$(find_external_monitor)"
    if [[ -z "$monitor" ]]; then
      local warn_msg="No external monitor found, falling back to $PRIMARY_MONITOR"
      echo -e "${YELLOW}!${RESET} $warn_msg"
      send_notification "No External Monitor" "$warn_msg"
      monitor="$PRIMARY_MONITOR"
    else
      send_notification "External Monitor Detected" "$monitor ($(get_monitor_info "$monitor"))"
    fi
  fi

  validate_monitor "$monitor" || fatal "Monitor '$monitor' not found."

  local current_monitor
  current_monitor="$(get_active_monitor)"

  echo -e "\n${BOLD}Hyprland Workspace Router${RESET}"
  echo "Current:   $current_monitor"
  echo "Target:    $monitor"
  echo "Workspace: $workspace"
  echo "Delay:     ${SLEEP_DURATION}s"
  echo

  if [[ "$current_monitor" == "$monitor" ]]; then
    info "Already on $monitor, switching workspace only."
    run_hyprctl "workspace $workspace" "Switching to workspace $workspace"
  else
    run_hyprctl "focusmonitor $monitor" "Focusing monitor $monitor"
    sleep "$SLEEP_DURATION"
    run_hyprctl "workspace $workspace" "Switching to workspace $workspace"
  fi

  ok "Done."
  send_notification "hypr-session-route" "$monitor ($(get_monitor_info "$monitor")) -> Workspace $workspace" "normal" "emblem-success"
}

main "$@"
