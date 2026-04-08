#!/usr/bin/env bash
# ==============================================================================
# Script: niri-two-column-layout
# Description: Apply a fixed two-column split on the focused Niri workspace.
# Usage: niri-two-column-layout [--left 65] [--right 35] [--dry-run]
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMMON_HELPER="${SCRIPT_DIR}/niri-session-common.sh"
[[ -r "${COMMON_HELPER}" ]] || COMMON_HELPER="${SCRIPT_DIR}/niri-session-common"
# shellcheck source=niri-session-common.sh
source "${COMMON_HELPER}"

LOG_TAG="niri-two-column-layout"

log() { printf '[%s] %s\n' "${LOG_TAG}" "$*" >&2; }
die() { printf '[%s] ERROR: %s\n' "${LOG_TAG}" "$*" >&2; exit 1; }

usage() {
  cat <<'EOF'
Usage:
  niri-two-column-layout [--left 65] [--right 35] [--dry-run]

Description:
  Focused workspace'teki iki tiling kolonu sabit bir orana getirir.
  Varsayilan davranis:
    - soldaki kolon 65%
    - sagdaki kolon 35%

Notes:
  - Sadece mevcut workspace'te tam olarak 2 tiling kolon varsa calisir.
  - Floating pencereler yok sayilir.
  - Islem sonunda odaklanan pencere geri yuklenir.

Examples:
  niri-two-column-layout
  niri-two-column-layout --left 70 --right 30
  niri-two-column-layout --dry-run
EOF
}

ensure_niri_env() {
  niri_ensure_runtime_dir
  niri_ensure_session_identity
  niri_detect_wayland_display
  niri_detect_socket
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "required command not found: $1"
}

normalize_width() {
  local raw="${1:-}"

  if [[ "${raw}" =~ ^[0-9]+$ ]]; then
    printf '%s%%\n' "${raw}"
    return 0
  fi

  if [[ "${raw}" =~ ^[0-9]+%$ ]]; then
    printf '%s\n' "${raw}"
    return 0
  fi

  die "invalid width '${raw}' (use 65 or 65%)"
}

width_value() {
  local raw="${1:-}"
  printf '%s\n' "${raw%%%}"
}

collect_columns() {
  local workspace_id="${1:?workspace id required}"
  local windows_json="${2:-}"

  jq -r --argjson workspace_id "${workspace_id}" '
    [
      .[]?
      | select(.workspace_id == $workspace_id)
      | select(.is_floating == false)
      | select((.layout.pos_in_scrolling_layout // []) | length >= 1)
      | {
          id: (.id | tostring),
          col: (.layout.pos_in_scrolling_layout[0]),
          row: (.layout.pos_in_scrolling_layout[1] // 0)
        }
    ]
    | group_by(.col)
    | map(sort_by(.row, .id)[0])
    | sort_by(.col)
    | .[] | [.id, (.col | tostring)] | @tsv
  ' <<<"${windows_json}"
}

run_action() {
  local dry_run="${1:?dry-run flag required}"
  shift

  if [[ "${dry_run}" == "1" ]]; then
    log "dry-run: niri msg action $*"
    return 0
  fi

  niri msg action "$@" >/dev/null 2>&1 || die "failed to run: niri msg action $*"
}

main() {
  local left_raw="65"
  local right_raw="35"
  local dry_run="0"

  while (($#)); do
    case "$1" in
      --left)
        [[ $# -ge 2 ]] || die "missing value for --left"
        left_raw="$2"
        shift 2
        ;;
      --right)
        [[ $# -ge 2 ]] || die "missing value for --right"
        right_raw="$2"
        shift 2
        ;;
      --dry-run)
        dry_run="1"
        shift
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        die "unknown argument: $1"
        ;;
    esac
  done

  local left_width right_width left_value right_value
  left_width="$(normalize_width "${left_raw}")"
  right_width="$(normalize_width "${right_raw}")"
  left_value="$(width_value "${left_width}")"
  right_value="$(width_value "${right_width}")"

  (( left_value >= 1 && left_value <= 99 )) || die "--left must be between 1 and 99"
  (( right_value >= 1 && right_value <= 99 )) || die "--right must be between 1 and 99"
  (( left_value + right_value == 100 )) || die "left and right widths must add up to 100"

  ensure_niri_env || true
  require_cmd niri
  require_cmd jq

  niri msg version >/dev/null 2>&1 || die "cannot connect to niri"

  local focused_window_json workspaces_json windows_json
  local focused_window_id workspace_id

  focused_window_json="$(niri msg --json focused-window 2>/dev/null || true)"
  focused_window_id="$(jq -r '.id // empty' <<<"${focused_window_json:-null}" 2>/dev/null || true)"
  workspace_id="$(jq -r '.workspace_id // empty' <<<"${focused_window_json:-null}" 2>/dev/null || true)"

  if [[ ! "${workspace_id}" =~ ^[0-9]+$ ]]; then
    workspaces_json="$(niri msg --json workspaces 2>/dev/null || true)"
    workspace_id="$(jq -r 'first(.[]? | select(.is_focused == true) | .id) // empty' <<<"${workspaces_json}" 2>/dev/null || true)"
  fi

  [[ "${workspace_id}" =~ ^[0-9]+$ ]] || die "could not resolve focused workspace"

  windows_json="$(niri msg --json windows 2>/dev/null || true)"
  [[ -n "${windows_json}" ]] || die "failed to query niri windows"

  local -a columns=()
  mapfile -t columns < <(collect_columns "${workspace_id}" "${windows_json}")

  (( ${#columns[@]} == 2 )) || die "focused workspace must have exactly 2 tiling columns; found ${#columns[@]}"

  local left_id left_col right_id right_col
  left_id="${columns[0]%%$'\t'*}"
  left_col="${columns[0]#*$'\t'}"
  right_id="${columns[1]%%$'\t'*}"
  right_col="${columns[1]#*$'\t'}"

  [[ "${left_id}" =~ ^[0-9]+$ ]] || die "failed to resolve left column window id"
  [[ "${right_id}" =~ ^[0-9]+$ ]] || die "failed to resolve right column window id"
  [[ "${left_col}" != "${right_col}" ]] || die "detected only one tiling column"

  log "workspace ${workspace_id}: left window ${left_id} -> ${left_width}, right window ${right_id} -> ${right_width}"

  run_action "${dry_run}" focus-window --id "${left_id}"
  run_action "${dry_run}" move-column-to-first
  run_action "${dry_run}" set-column-width "${left_width}"

  run_action "${dry_run}" focus-window --id "${right_id}"
  run_action "${dry_run}" move-column-to-last
  run_action "${dry_run}" set-column-width "${right_width}"

  if [[ "${focused_window_id}" =~ ^[0-9]+$ ]]; then
    run_action "${dry_run}" focus-window --id "${focused_window_id}"
  fi
}

main "$@"
