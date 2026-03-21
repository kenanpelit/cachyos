#!/usr/bin/env bash
# ==============================================================================
# Script: niri-float-sticky.sh
# Description: Event-driven floating sticky daemon for Niri with toggle helpers.
# Usage: niri-float-sticky.sh [daemon|list|set-active|unset-active|clear-active|toggle-active|set-id <id>|unset-id <id>|clear-id <id>|toggle-id <id>] [options]
# ==============================================================================

set -euo pipefail

SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
VERSION="0.1.0"

RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"
STATE_DIR="${STATE_HOME}/niri-float-sticky"
STATE_FILE="${STATE_DIR}/state.json"
STATE_LOCK_FILE="${STATE_DIR}/state.lock"
DAEMON_LOCK_FILE="${RUNTIME_DIR}/niri-float-sticky.lock"
PID_FILE="${RUNTIME_DIR}/niri-float-sticky.pid"

AUTO_STICK="${NIRI_FLOAT_STICKY_AUTO_STICK:-0}"
ALLOW_FOREIGN_MONITORS="${NIRI_FLOAT_STICKY_ALLOW_FOREIGN_MONITORS:-0}"
APP_ID_REGEX="${NIRI_FLOAT_STICKY_APP_ID_REGEX:-}"
TITLE_REGEX="${NIRI_FLOAT_STICKY_TITLE_REGEX:-}"
RECONNECT_DELAY="${NIRI_FLOAT_STICKY_RECONNECT_DELAY:-1}"
NOTIFY_ENABLED="${NIRI_FLOAT_STICKY_NOTIFY:-1}"
NOTIFY_TIMEOUT="${NIRI_FLOAT_STICKY_NOTIFY_TIMEOUT:-1400}"
DEBUG_ENABLED="${NIRI_FLOAT_STICKY_DEBUG:-0}"

log() {
  printf '[niri-float-sticky] %s\n' "$*" >&2
}

debug() {
  [[ "${DEBUG_ENABLED}" == "1" ]] || return 0
  log "DEBUG: $*"
}

die() {
  log "ERROR: $*"
  exit 1
}

notify_msg() {
  local title="$1"
  local body="$2"
  [[ "${NOTIFY_ENABLED}" == "1" ]] || return 0
  command -v notify-send >/dev/null 2>&1 || return 0
  notify-send \
    -a "niri-float-sticky" \
    -u low \
    -t "${NOTIFY_TIMEOUT}" \
    -h "string:x-canonical-private-synchronous:niri-float-sticky" \
    "$title" "$body" >/dev/null 2>&1 || true
}

usage() {
  cat <<'EOF'
Usage:
  niri-float-sticky.sh [command] [options]

Commands:
  daemon
  list
  set-active
  unset-active
  clear-active
  toggle-active
  set-id <window_id>
  unset-id <window_id>
  clear-id <window_id>
  toggle-id <window_id>

Options:
  -ipc <set_sticky|unset_sticky|toggle_sticky|clear_override>
  -allow-moving-to-foreign-monitors
  -disable-auto-stick
  -app-id <regex>
  -title <regex>
  -debug
  -version
  -h, --help

Environment:
  NIRI_FLOAT_STICKY_AUTO_STICK=0|1
  NIRI_FLOAT_STICKY_ALLOW_FOREIGN_MONITORS=0|1
  NIRI_FLOAT_STICKY_APP_ID_REGEX=<regex>
  NIRI_FLOAT_STICKY_TITLE_REGEX=<regex>
EOF
}

need_bins() {
  command -v niri >/dev/null 2>&1 || die "niri not found in PATH"
  command -v jq >/dev/null 2>&1 || die "jq not found in PATH"
  command -v flock >/dev/null 2>&1 || die "flock not found in PATH"
}

ensure_dirs() {
  mkdir -p "${STATE_DIR}" "${RUNTIME_DIR}"
}

tmpfile() {
  ensure_dirs
  mktemp "${STATE_DIR}/.tmp.XXXXXX"
}

with_state_lock() {
  ensure_dirs
  touch "${STATE_LOCK_FILE}"
  (
    flock -x 9 || exit 1
    "$@"
  ) 9>"${STATE_LOCK_FILE}"
}

init_state_locked() {
  ensure_dirs
  if ! jq -e . "${STATE_FILE}" >/dev/null 2>&1; then
    printf '%s\n' '{"manual":{}}' >"${STATE_FILE}"
  fi

  local tmp
  tmp="$(tmpfile)"
  if jq '
      if type != "object" then {} else . end
      | .manual = (
          if (.manual | type) == "object"
          then with_entries(select(.value == true or .value == false))
          else {}
          end
        )
    ' "${STATE_FILE}" >"${tmp}" 2>/dev/null; then
    mv "${tmp}" "${STATE_FILE}"
  else
    rm -f "${tmp}"
    printf '%s\n' '{"manual":{}}' >"${STATE_FILE}"
  fi
}

state_update_locked() {
  local jq_program="$1"
  shift

  local tmp
  tmp="$(tmpfile)"
  if jq "$@" "${jq_program}" "${STATE_FILE}" >"${tmp}"; then
    mv "${tmp}" "${STATE_FILE}"
  else
    rm -f "${tmp}"
    die "failed to update state"
  fi
}

manual_json_locked() {
  jq -c '.manual // {}' "${STATE_FILE}"
}

set_manual_override_locked() {
  local window_id="$1"
  local value="$2"
  state_update_locked '.manual[$id] = $value' --arg id "${window_id}" --argjson value "${value}"
}

clear_manual_override_locked() {
  local window_id="$1"
  state_update_locked 'del(.manual[$id])' --arg id "${window_id}"
}

prune_manual_locked_with_windows() {
  local windows_json="$1"
  local live_ids
  live_ids="$(jq '[.[]? | .id | tostring]' <<<"${windows_json}")"
  state_update_locked '
    .manual = ((.manual // {}) | with_entries(select(($live | index(.key)) != null)))
  ' --argjson live "${live_ids}"
}

live_windows_json() {
  niri msg -j windows 2>/dev/null
}

live_workspaces_json() {
  niri msg -j workspaces 2>/dev/null
}

focused_window_id() {
  niri msg -j focused-window 2>/dev/null | jq -r '.id // empty'
}

require_window_id() {
  [[ "$1" =~ ^[0-9]+$ ]] || die "window_id must be numeric: $1"
}

window_exists_json() {
  local window_id="$1"
  local windows_json="$2"
  jq -e --arg id "${window_id}" 'any(.[]?; (.id | tostring) == $id)' <<<"${windows_json}" >/dev/null 2>&1
}

workspace_output_by_id() {
  local workspace_id="$1"
  local workspaces_json="$2"
  jq -r --arg id "${workspace_id}" '
    first(.[]? | select((.id | tostring) == $id) | (.output // "")) // ""
  ' <<<"${workspaces_json}" 2>/dev/null || true
}

effective_sticky_for_window() {
  local window_id="$1"
  local windows_json="$2"
  local manual_json="$3"

  jq -nr \
    --arg id "${window_id}" \
    --argjson wins "${windows_json}" \
    --argjson manual "${manual_json}" \
    --arg auto "${AUTO_STICK}" \
    --arg app_re "${APP_ID_REGEX}" \
    --arg title_re "${TITLE_REGEX}" '
      def matches(re; value):
        if re == "" then true else ((value // "") | test(re)) end;
      first($wins[]? | select((.id | tostring) == $id)) as $w
      | if $w == null then false
        else
          ($manual[$id] // null) as $override
          | if $override != null then
              $override
            else
              (($w.is_floating == true)
               and ($auto == "1")
               and matches($app_re; $w.app_id)
               and matches($title_re; $w.title))
            end
        end
    '
}

current_sticky_entries() {
  local windows_json="$1"
  local manual_json="$2"

  jq -r \
    --argjson manual "${manual_json}" \
    --arg auto "${AUTO_STICK}" \
    --arg app_re "${APP_ID_REGEX}" \
    --arg title_re "${TITLE_REGEX}" '
      def matches(re; value):
        if re == "" then true else ((value // "") | test(re)) end;
      .[]?
      | select(.is_floating == true and .workspace_id != null)
      | (.id | tostring) as $id
      | ($manual[$id] // null) as $override
      | (
          if $override != null then
            $override
          else
            (($auto == "1")
             and matches($app_re; .app_id)
             and matches($title_re; .title))
          end
        ) as $sticky
      | select($sticky == true)
      | [$id, (.workspace_id | tostring), (.app_id // ""), (.title // "")]
      | @tsv
    ' <<<"${windows_json}"
}

current_sticky_ids_json() {
  local windows_json="$1"
  local manual_json="$2"

  jq -c \
    --argjson manual "${manual_json}" \
    --arg auto "${AUTO_STICK}" \
    --arg app_re "${APP_ID_REGEX}" \
    --arg title_re "${TITLE_REGEX}" '
      def matches(re; value):
        if re == "" then true else ((value // "") | test(re)) end;
      [
        .[]?
        | select(.is_floating == true and .workspace_id != null)
        | (.id | tostring) as $id
        | ($manual[$id] // null) as $override
        | (
            if $override != null then
              $override
            else
              (($auto == "1")
               and matches($app_re; .app_id)
               and matches($title_re; .title))
            end
          ) as $sticky
        | select($sticky == true)
        | (.id | tonumber)
      ]
    ' <<<"${windows_json}"
}

move_window_to_workspace() {
  local window_id="$1"
  local workspace_id="$2"
  niri msg action move-window-to-workspace --window-id "${window_id}" --focus false "${workspace_id}" >/dev/null 2>&1
}

sync_to_workspace() {
  local workspace_id="$1"
  local windows_json workspaces_json manual_json target_output
  local entry window_id current_ws window_output app_id title

  windows_json="$(live_windows_json || true)"
  [[ -n "${windows_json}" ]] || return 0

  workspaces_json="$(live_workspaces_json || true)"
  [[ -n "${workspaces_json}" ]] || return 0

  with_state_lock init_state_locked
  with_state_lock prune_manual_locked_with_windows "${windows_json}"
  manual_json="$(with_state_lock manual_json_locked)"
  target_output="$(workspace_output_by_id "${workspace_id}" "${workspaces_json}")"

  while IFS=$'\t' read -r window_id current_ws app_id title; do
    [[ -n "${window_id}" ]] || continue
    [[ "${current_ws}" == "${workspace_id}" ]] && continue

    if [[ "${ALLOW_FOREIGN_MONITORS}" != "1" ]]; then
      window_output="$(workspace_output_by_id "${current_ws}" "${workspaces_json}")"
      if [[ -n "${target_output}" && -n "${window_output}" && "${target_output}" != "${window_output}" ]]; then
        debug "skip window ${window_id} on foreign monitor (${window_output} -> ${target_output})"
        continue
      fi
    fi

    debug "move sticky window ${window_id} to workspace ${workspace_id}"
    move_window_to_workspace "${window_id}" "${workspace_id}" || true
  done < <(current_sticky_entries "${windows_json}" "${manual_json}")
}

current_workspace_id() {
  local workspaces_json
  workspaces_json="$(live_workspaces_json || true)"
  jq -r '
    first(.[]? | select(.is_focused == true) | .id)
    // first(.[]? | select(.is_active == true) | .id)
    // empty
  ' <<<"${workspaces_json}" 2>/dev/null || true
}

prune_manual_state() {
  local windows_json
  windows_json="$(live_windows_json || true)"
  [[ -n "${windows_json}" ]] || return 0
  with_state_lock init_state_locked
  with_state_lock prune_manual_locked_with_windows "${windows_json}"
}

daemon_running() {
  [[ -f "${PID_FILE}" ]] || return 1
  local pid
  pid="$(cat "${PID_FILE}" 2>/dev/null || true)"
  [[ "${pid}" =~ ^[0-9]+$ ]] || return 1
  kill -0 "${pid}" 2>/dev/null
}

ensure_daemon_running() {
  daemon_running && return 0
  debug "starting daemon in background"
  "${SCRIPT_PATH}" daemon >/dev/null 2>&1 &
  disown || true
  sleep 0.2
}

set_window_override() {
  local window_id="$1"
  local value="$2"
  local windows_json

  windows_json="$(live_windows_json || true)"
  [[ -n "${windows_json}" ]] || die "failed to query niri windows"
  window_exists_json "${window_id}" "${windows_json}" || die "Window not found in Niri: ${window_id}"

  with_state_lock init_state_locked
  with_state_lock prune_manual_locked_with_windows "${windows_json}"
  with_state_lock set_manual_override_locked "${window_id}" "${value}"
  ensure_daemon_running

  if [[ "${value}" == "true" ]]; then
    printf 'Sticky enabled for window %s\n' "${window_id}"
  else
    printf 'Sticky disabled for window %s\n' "${window_id}"
  fi
}

clear_window_override() {
  local window_id="$1"
  local windows_json

  windows_json="$(live_windows_json || true)"
  [[ -n "${windows_json}" ]] || die "failed to query niri windows"
  window_exists_json "${window_id}" "${windows_json}" || die "Window not found in Niri: ${window_id}"

  with_state_lock init_state_locked
  with_state_lock prune_manual_locked_with_windows "${windows_json}"
  with_state_lock clear_manual_override_locked "${window_id}"
  ensure_daemon_running

  printf 'Sticky override cleared for window %s\n' "${window_id}"
}

toggle_window_override() {
  local window_id="$1"
  local windows_json manual_json current

  windows_json="$(live_windows_json || true)"
  [[ -n "${windows_json}" ]] || die "failed to query niri windows"
  window_exists_json "${window_id}" "${windows_json}" || die "Window not found in Niri: ${window_id}"

  with_state_lock init_state_locked
  with_state_lock prune_manual_locked_with_windows "${windows_json}"
  manual_json="$(with_state_lock manual_json_locked)"
  current="$(effective_sticky_for_window "${window_id}" "${windows_json}" "${manual_json}")"

  if [[ "${current}" == "true" ]]; then
    with_state_lock set_manual_override_locked "${window_id}" false
    ensure_daemon_running
    printf 'Sticky disabled for window %s\n' "${window_id}"
  else
    with_state_lock set_manual_override_locked "${window_id}" true
    ensure_daemon_running
    printf 'Sticky enabled for window %s\n' "${window_id}"
  fi
}

active_or_die() {
  local window_id
  window_id="$(focused_window_id)"
  [[ -n "${window_id}" ]] || die "Active window not found"
  printf '%s\n' "${window_id}"
}

list_sticky() {
  local windows_json manual_json

  windows_json="$(live_windows_json || true)"
  [[ -n "${windows_json}" ]] || {
    printf '[]\n'
    return 0
  }

  with_state_lock init_state_locked
  with_state_lock prune_manual_locked_with_windows "${windows_json}"
  manual_json="$(with_state_lock manual_json_locked)"
  current_sticky_ids_json "${windows_json}" "${manual_json}"
}

handle_ipc_action() {
  local action="$1"
  local window_id
  window_id="$(active_or_die)"

  case "${action}" in
    set_sticky) set_window_override "${window_id}" true ;;
    unset_sticky) set_window_override "${window_id}" false ;;
    toggle_sticky) toggle_window_override "${window_id}" ;;
    clear_override) clear_window_override "${window_id}" ;;
    *) die "invalid ipc action: ${action}" ;;
  esac
}

handle_event_line() {
  local line="$1"
  local event_name workspace_id

  [[ -n "${line}" ]] || return 0
  event_name="$(jq -r 'keys[0] // empty' <<<"${line}" 2>/dev/null || true)"

  case "${event_name}" in
    WorkspaceActivated)
      workspace_id="$(jq -r '.WorkspaceActivated.id // empty' <<<"${line}" 2>/dev/null || true)"
      [[ -n "${workspace_id}" ]] || return 0
      debug "workspace activated: ${workspace_id}"
      sync_to_workspace "${workspace_id}" || true
      ;;
    WindowClosed|WindowsChanged|WindowOpenedOrChanged)
      debug "prune manual state after ${event_name}"
      prune_manual_state || true
      ;;
    WorkspacesChanged)
      debug "workspaces changed"
      ;;
  esac
}

run_daemon() {
  need_bins
  ensure_dirs

  exec 8>"${DAEMON_LOCK_FILE}"
  flock -n 8 || {
    debug "daemon already running"
    exit 0
  }

  printf '%s\n' "$$" >"${PID_FILE}"
  trap 'rm -f "${PID_FILE}"' EXIT

  with_state_lock init_state_locked
  prune_manual_state || true

  local workspace_id
  workspace_id="$(current_workspace_id || true)"
  if [[ -n "${workspace_id}" ]]; then
    sync_to_workspace "${workspace_id}" || true
  fi

  log "daemon started (auto=${AUTO_STICK}, foreign=${ALLOW_FOREIGN_MONITORS})"

  while true; do
    while IFS= read -r line; do
      handle_event_line "${line}"
    done < <(niri msg event-stream 2>/dev/null || true)

    debug "event stream ended; reconnecting in ${RECONNECT_DELAY}s"
    sleep "${RECONNECT_DELAY}"
  done
}

parse_args() {
  local ipc_action=""
  local app_arg title_arg
  local -a app_patterns=()
  local -a title_patterns=()
  local command=""
  local -a command_args=()

  while [[ $# -gt 0 ]]; do
    case "$1" in
      -allow-moving-to-foreign-monitors)
        ALLOW_FOREIGN_MONITORS=1
        shift
        ;;
      -disable-auto-stick)
        AUTO_STICK=0
        shift
        ;;
      -app-id)
        [[ $# -ge 2 ]] || die "-app-id requires a regex"
        app_patterns+=("$2")
        shift 2
        ;;
      -title)
        [[ $# -ge 2 ]] || die "-title requires a regex"
        title_patterns+=("$2")
        shift 2
        ;;
      -ipc)
        [[ $# -ge 2 ]] || die "-ipc requires an action"
        ipc_action="$2"
        shift 2
        ;;
      -debug)
        DEBUG_ENABLED=1
        shift
        ;;
      -version)
        printf 'niri-float-sticky %s\n' "${VERSION}"
        exit 0
        ;;
      -h|--help|help)
        usage
        exit 0
        ;;
      *)
        command="$1"
        shift
        command_args=("$@")
        break
        ;;
    esac
  done

  if (( ${#app_patterns[@]} > 0 )); then
    APP_ID_REGEX="$(IFS='|'; printf '%s' "${app_patterns[*]}")"
  fi
  if (( ${#title_patterns[@]} > 0 )); then
    TITLE_REGEX="$(IFS='|'; printf '%s' "${title_patterns[*]}")"
  fi

  if [[ -n "${ipc_action}" ]]; then
    handle_ipc_action "${ipc_action}"
    exit 0
  fi

  if [[ -z "${command}" ]]; then
    command="daemon"
  fi

  case "${command}" in
    daemon)
      run_daemon
      ;;
    list)
      need_bins
      list_sticky
      ;;
    set-active)
      need_bins
      set_window_override "$(active_or_die)" true
      ;;
    unset-active)
      need_bins
      set_window_override "$(active_or_die)" false
      ;;
    clear-active)
      need_bins
      clear_window_override "$(active_or_die)"
      ;;
    toggle-active)
      need_bins
      toggle_window_override "$(active_or_die)"
      ;;
    set-id)
      need_bins
      [[ ${#command_args[@]} -eq 1 ]] || die "set-id requires <window_id>"
      require_window_id "${command_args[0]}"
      set_window_override "${command_args[0]}" true
      ;;
    unset-id)
      need_bins
      [[ ${#command_args[@]} -eq 1 ]] || die "unset-id requires <window_id>"
      require_window_id "${command_args[0]}"
      set_window_override "${command_args[0]}" false
      ;;
    clear-id)
      need_bins
      [[ ${#command_args[@]} -eq 1 ]] || die "clear-id requires <window_id>"
      require_window_id "${command_args[0]}"
      clear_window_override "${command_args[0]}"
      ;;
    toggle-id)
      need_bins
      [[ ${#command_args[@]} -eq 1 ]] || die "toggle-id requires <window_id>"
      require_window_id "${command_args[0]}"
      toggle_window_override "${command_args[0]}"
      ;;
    *)
      die "unknown command: ${command}"
      ;;
  esac
}

parse_args "$@"
