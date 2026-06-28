#!/usr/bin/env bash
# shellcheck disable=SC2329
# ==============================================================================
# Script: screenshot.sh
# Description: Screenshot helper for the margo Wayland compositor, with a
#              generic Wayland fallback (grim / slurp / wl-copy).
# Usage: screenshot.sh [action]
# ==============================================================================

set -euo pipefail

SCRIPT_NAME="$(basename "$0")"
SCRIPT_VERSION="3.0.0"

PICTURES_DIR="$(xdg-user-dir PICTURES 2>/dev/null || printf '%s\n' "$HOME/Pictures")"
SAVE_DIR="${SCREENSHOT_SAVE_DIR:-$PICTURES_DIR/Screenshots}"
TEMP_DIR="${XDG_RUNTIME_DIR:-/tmp}/screenshot-tool-${UID}"

# Keep the capture overlay neutral so the selected area doesn't look tinted.
SLURP_BACKGROUND="${SCREENSHOT_SLURP_BACKGROUND:-#00000055}"
SLURP_BORDER="${SCREENSHOT_SLURP_BORDER:-#f5f5f5ee}"
SLURP_SELECTION="${SCREENSHOT_SLURP_SELECTION:-#00000000}"
SLURP_BORDER_WIDTH="${SCREENSHOT_SLURP_BORDER_WIDTH:-3}"
COLOR_PICKER_BORDER="${SCREENSHOT_COLOR_PICKER_BORDER:-#e01b24ff}"

EDITORS=("swappy" "satty" "gimp" "krita")
FILENAME_FORMAT="screenshot_%Y-%m-%d_%H-%M-%S.png"

EXIT_SUCCESS=0
EXIT_INVALID_OPTION=1
EXIT_MISSING_DEPENDENCY=2
EXIT_CANCELLED=3
EXIT_UNSUPPORTED=4

TEMP_FILES=()

cleanup_temp_files() {
  local file
  for file in "${TEMP_FILES[@]:-}"; do
    [[ -n "${file:-}" ]] || continue
    rm -f "$file" 2>/dev/null || true
  done
}
trap cleanup_temp_files EXIT

detect_env() {
  local raw desktop

  raw="${XDG_CURRENT_DESKTOP:-${XDG_SESSION_DESKTOP:-${DESKTOP_SESSION:-}}}"
  raw="${raw%%:*}"
  desktop="$(printf '%s' "$raw" | tr '[:upper:]' '[:lower:]')"

  case "$desktop" in
  margo)
    printf '%s\n' "margo"
    return 0
    ;;
  esac

  # `mctl` is the margo CLI; `mctl status` succeeds only inside a live
  # margo session. Fall back to a generic Wayland session otherwise.
  if command -v mctl >/dev/null 2>&1 && mctl status >/dev/null 2>&1; then
    printf '%s\n' "margo"
  elif [[ -n "${WAYLAND_DISPLAY:-}" ]]; then
    printf '%s\n' "wayland"
  else
    printf '%s\n' "unknown"
  fi
}

CURRENT_ENV="$(detect_env)"

show_notification() {
  local title="$1"
  local message="$2"
  local urgency="${3:-normal}"
  local icon="${4:-preferences-desktop-screensaver}"

  command -v notify-send >/dev/null 2>&1 || return 0

  notify-send \
    -h string:x-canonical-private-synchronous:screenshot-tool \
    -t 2200 \
    -u "$urgency" \
    -i "$icon" \
    "$title" \
    "$message"
}

select_editor() {
  local editor
  for editor in "${EDITORS[@]}"; do
    if command -v "$editor" >/dev/null 2>&1; then
      printf '%s\n' "$editor"
      return 0
    fi
  done
  printf '%s\n' "none"
}

EDITOR="$(select_editor)"

normalize_action() {
  case "${1:-ri}" in
  "" | default) printf '%s\n' "ri" ;;
  rc | region-copy) printf '%s\n' "rc" ;;
  rf | region-save | region-file) printf '%s\n' "rf" ;;
  ri | region-edit | region) printf '%s\n' "ri" ;;
  rec | region-edit-copy) printf '%s\n' "rec" ;;
  sc | screen-copy) printf '%s\n' "sc" ;;
  sf | screen-save | screen-file) printf '%s\n' "sf" ;;
  si | screen-edit) printf '%s\n' "si" ;;
  sec | screen-edit-copy) printf '%s\n' "sec" ;;
  p | pick | color) printf '%s\n' "p" ;;
  o | open) printf '%s\n' "open" ;;
  d | dir) printf '%s\n' "dir" ;;
  help | -h | --help) printf '%s\n' "help" ;;
  version | -v | --version) printf '%s\n' "version" ;;
  *) printf '%s\n' "$1" ;;
  esac
}

ACTION="$(normalize_action "${1:-ri}")"

create_temp_dir() {
  mkdir -p "$TEMP_DIR"
}

cleanup_old_temp_files() {
  [[ -d "$TEMP_DIR" ]] || return 0
  find "$TEMP_DIR" -maxdepth 1 -type f -name 'screenshot_*.png' -mtime +1 -delete 2>/dev/null || true
}

create_screenshot_dir() {
  mkdir -p "$SAVE_DIR"
}

register_temp_file() {
  TEMP_FILES+=("$1")
}

make_temp_png() {
  local tmp
  create_temp_dir
  tmp="$(mktemp "$TEMP_DIR/screenshot_XXXXXX.png")"
  register_temp_file "$tmp"
  printf '%s\n' "$tmp"
}

get_filename() {
  date +"$FILENAME_FORMAT"
}

copy_image_to_clipboard() {
  wl-copy --type image/png <"$1"
}

copy_text_to_clipboard() {
  printf '%s' "$1" | wl-copy
}

show_help() {
  cat <<EOF
╭─────────────────────────────────────────────╮
│        Screenshot Helper                    │
│             Version $SCRIPT_VERSION         │
│         Environment: $CURRENT_ENV           │
╰─────────────────────────────────────────────╯

Usage: $SCRIPT_NAME [ACTION]

Actions:
  rc   Region -> clipboard
  rf   Region -> file
  ri   Region -> editor -> file
  rec  Region -> editor -> file + clipboard
  sc   Screen -> clipboard
  sf   Screen -> file
  si   Screen -> editor -> file
  sec  Screen -> editor -> file + clipboard
  p    Pick color
  o    Open latest screenshot
  d    Open screenshot directory

Notes:
- Default action with no args: ri
- Capture uses the generic Wayland tools grim/slurp/wl-copy.
- Screen actions capture all outputs via grim.
- Active editor: $EDITOR
- Save directory: $SAVE_DIR
EOF
}

show_version() {
  printf '%s %s\n' "$SCRIPT_NAME" "$SCRIPT_VERSION"
}

require_commands() {
  local missing=()
  local cmd

  for cmd in "$@"; do
    command -v "$cmd" >/dev/null 2>&1 || missing+=("$cmd")
  done

  if ((${#missing[@]} > 0)); then
    show_notification "Missing dependencies" "Please install: ${missing[*]}" "critical"
    return $EXIT_MISSING_DEPENDENCY
  fi
}

check_action_dependencies() {
  local action="$1"

  case "$action" in
  help | version | open | dir)
    return 0
    ;;
  p)
    require_commands wl-copy grim slurp || return $?
    if ! command -v magick >/dev/null 2>&1 && ! command -v convert >/dev/null 2>&1; then
      show_notification "Missing dependencies" "Please install: ImageMagick (magick or convert)" "critical"
      return $EXIT_MISSING_DEPENDENCY
    fi
    return 0
    ;;
  esac

  case "$action" in
  rc | sc | rec | sec)
    require_commands wl-copy || return $?
    ;;
  esac

  case "$action" in
  rc | rf | ri | rec)
    require_commands grim slurp || return $?
    ;;
  sc | sf | si | sec)
    require_commands grim || return $?
    ;;
  esac

  case "$action" in
  ri | rec | si | sec)
    if [[ "$EDITOR" == "none" ]]; then
      show_notification "Missing dependencies" "Please install swappy or satty for editing" "critical"
      return $EXIT_MISSING_DEPENDENCY
    fi
    ;;
  esac

  return 0
}

handle_capture_failure() {
  local status="$1"
  local label="$2"

  case "$status" in
  "$EXIT_CANCELLED")
    return 0
    ;;
  "$EXIT_MISSING_DEPENDENCY") ;;
  *)
    show_notification "Screenshot" "$label failed" "critical"
    ;;
  esac

  return "$status"
}

take_region_screenshot() {
  local filename="$1"
  local geometry

  geometry="$(slurp -b "$SLURP_BACKGROUND" -c "$SLURP_BORDER" -s "$SLURP_SELECTION" -w "$SLURP_BORDER_WIDTH" 2>/dev/null || true)"
  [[ -n "$geometry" ]] || return "$EXIT_CANCELLED"

  grim -g "$geometry" "$filename"
}

take_screen_screenshot() {
  local filename="$1"

  # TODO: margo equivalent — capture only the focused output. margo's
  # mctl exposes no focused-output query, so for now grab all outputs
  # via plain grim.
  grim "$filename"
}

open_in_editor() {
  local input="$1"
  local output="$2"

  case "$EDITOR" in
  swappy)
    "$EDITOR" -f "$input" -o "$output"
    ;;
  satty)
    "$EDITOR" --filename "$input" --output-filename "$output"
    ;;
  gimp | krita)
    "$EDITOR" "$input" >/dev/null 2>&1 &
    show_notification "Editor" "$EDITOR opened. Save manually if needed."
    return 0
    ;;
  *)
    return $EXIT_MISSING_DEPENDENCY
    ;;
  esac
}

run_capture_flow() {
  local capture_fn="$1"
  local mode="$2"
  local label="$3"
  local temp_file output_file
  local status

  case "$mode" in
  copy)
    temp_file="$(make_temp_png)"
    if "$capture_fn" "$temp_file"; then
      copy_image_to_clipboard "$temp_file"
      show_notification "Screenshot" "$label copied to clipboard" "normal" "edit-copy"
    else
      status=$?
      handle_capture_failure "$status" "$label" || return "$status"
    fi
    ;;
  save)
    create_screenshot_dir
    output_file="$SAVE_DIR/$(get_filename)"
    if "$capture_fn" "$output_file"; then
      show_notification "Screenshot" "$label saved: $(basename "$output_file")" "normal" "document-save"
    else
      status=$?
      handle_capture_failure "$status" "$label" || return "$status"
    fi
    ;;
  edit | edit-copy)
    create_screenshot_dir
    temp_file="$(make_temp_png)"
    output_file="$SAVE_DIR/$(get_filename)"
    if "$capture_fn" "$temp_file"; then
      if open_in_editor "$temp_file" "$output_file"; then
        if [[ "$EDITOR" == "gimp" || "$EDITOR" == "krita" ]]; then
          show_notification "Screenshot" "$label opened in $EDITOR"
        elif [[ -s "$output_file" ]]; then
          if [[ "$mode" == "edit-copy" ]]; then
            copy_image_to_clipboard "$output_file"
            show_notification "Screenshot" "$label saved and copied" "normal" "edit-copy"
          else
            show_notification "Screenshot" "$label edited and saved" "normal" "document-edit"
          fi
        else
          show_notification "Screenshot" "$label editor closed without saving"
        fi
      else
        status=$?
        handle_capture_failure "$status" "$label" || return "$status"
      fi
    else
      status=$?
      handle_capture_failure "$status" "$label" || return "$status"
    fi
    ;;
  esac
}

open_last_screenshot() {
  local latest

  if [[ ! -d "$SAVE_DIR" ]]; then
    show_notification "Screenshot" "Screenshot directory does not exist" "critical"
    return 1
  fi

  latest="$(find "$SAVE_DIR" -type f -name '*.png' -printf '%T@ %p\n' 2>/dev/null | sort -n | tail -1 | cut -d' ' -f2-)"

  if [[ -n "$latest" ]]; then
    xdg-open "$latest" >/dev/null 2>&1 &
    show_notification "Screenshot" "Opened: $(basename "$latest")"
  else
    show_notification "Screenshot" "No screenshots found" "critical"
    return 1
  fi
}

open_screenshots_dir() {
  create_screenshot_dir
  xdg-open "$SAVE_DIR" >/dev/null 2>&1 &
  show_notification "Screenshot" "Opened directory: $SAVE_DIR"
}

pick_color() {
  local color point ppm

  point="$(slurp -p -b '#00000000' -c "$COLOR_PICKER_BORDER" -w "$SLURP_BORDER_WIDTH" 2>/dev/null || true)"
  [[ -n "$point" ]] || return $EXIT_CANCELLED

  ppm="$(grim -g "$point" -t ppm - 2>/dev/null || true)"
  [[ -n "$ppm" ]] || return 1

  if command -v magick >/dev/null 2>&1; then
    color="$(printf '%s' "$ppm" | magick - -format '%[pixel:p{0,0}]' txt:- 2>/dev/null | tail -n1 | awk '{print $4}')"
  else
    color="$(printf '%s' "$ppm" | convert - -format '%[pixel:p{0,0}]' txt:- 2>/dev/null | tail -n1 | awk '{print $4}')"
  fi

  [[ -n "$color" ]] || return 1
  printf '%s\n' "$color"
}

if [[ "$ACTION" == "help" ]]; then
  show_help
  exit $EXIT_SUCCESS
fi

if [[ "$ACTION" == "version" ]]; then
  show_version
  exit $EXIT_SUCCESS
fi

create_temp_dir
cleanup_old_temp_files

check_action_dependencies "$ACTION"

case "$ACTION" in
rc) run_capture_flow take_region_screenshot copy "Region screenshot" ;;
rf) run_capture_flow take_region_screenshot save "Region screenshot" ;;
ri) run_capture_flow take_region_screenshot edit "Region screenshot" ;;
rec) run_capture_flow take_region_screenshot edit-copy "Region screenshot" ;;
sc) run_capture_flow take_screen_screenshot copy "Screen screenshot" ;;
sf) run_capture_flow take_screen_screenshot save "Screen screenshot" ;;
si) run_capture_flow take_screen_screenshot edit "Screen screenshot" ;;
sec) run_capture_flow take_screen_screenshot edit-copy "Screen screenshot" ;;
p)
  color="$(pick_color)" || {
    status=$?
    handle_capture_failure "$status" "Color pick" || exit "$status"
    exit $EXIT_SUCCESS
  }
  copy_text_to_clipboard "$color"
  show_notification "Color Picker" "$color copied to clipboard" "normal" "color-select"
  printf '%s\n' "$color"
  ;;
open)
  open_last_screenshot
  ;;
dir)
  open_screenshots_dir
  ;;
*)
  show_notification "Screenshot" "Invalid action: $ACTION" "critical"
  show_help
  exit $EXIT_INVALID_OPTION
  ;;
esac

exit $EXIT_SUCCESS
