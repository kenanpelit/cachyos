#!/usr/bin/env bash
# shellcheck disable=SC2329
# ==============================================================================
# Script: screenshot.sh
# Description: Screenshot helper for MangoWM, Hyprland, Niri, Sway, and GNOME
# Usage: screenshot.sh [action]
# ==============================================================================

set -euo pipefail

SCRIPT_NAME="$(basename "$0")"
SCRIPT_VERSION="2.6.0"

PICTURES_DIR="$(xdg-user-dir PICTURES 2>/dev/null || printf '%s\n' "$HOME/Pictures")"
SAVE_DIR="${SCREENSHOT_SAVE_DIR:-$PICTURES_DIR/Screenshots}"
TEMP_DIR="${XDG_RUNTIME_DIR:-/tmp}/screenshot-tool-${UID}"

# Keep the capture overlay neutral so the selected area doesn't look tinted.
SLURP_BACKGROUND="${SCREENSHOT_SLURP_BACKGROUND:-#00000055}"
SLURP_BORDER="${SCREENSHOT_SLURP_BORDER:-#f5f5f5ee}"
SLURP_SELECTION="${SCREENSHOT_SLURP_SELECTION:-#00000000}"
SLURP_BORDER_WIDTH="${SCREENSHOT_SLURP_BORDER_WIDTH:-3}"
COLOR_PICKER_BORDER="${SCREENSHOT_COLOR_PICKER_BORDER:-#e01b24ff}"
NIRI_UI_TIMEOUT="${SCREENSHOT_NIRI_UI_TIMEOUT:-120}"
NIRI_REGION_SHOW_POINTER="${SCREENSHOT_NIRI_REGION_SHOW_POINTER:-false}"
NIRI_SCREEN_SHOW_POINTER="${SCREENSHOT_NIRI_SCREEN_SHOW_POINTER:-false}"
NIRI_WINDOW_SHOW_POINTER="${SCREENSHOT_NIRI_WINDOW_SHOW_POINTER:-true}"
SCREENSHOT_BACKEND="${SCREENSHOT_BACKEND:-auto}"

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
  mango | mangowm)
    printf '%s\n' "mango"
    return 0
    ;;
  gnome | hyprland | sway | niri)
    printf '%s\n' "$desktop"
    return 0
    ;;
  esac

  if [[ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]] || pgrep -x Hyprland >/dev/null 2>&1; then
    printf '%s\n' "hyprland"
  elif [[ -n "${NIRI_SOCKET:-}" ]] || pgrep -x niri >/dev/null 2>&1; then
    printf '%s\n' "niri"
  elif pgrep -x mango >/dev/null 2>&1 || pgrep -x mangowm >/dev/null 2>&1; then
    printf '%s\n' "mango"
  elif pgrep -x sway >/dev/null 2>&1; then
    printf '%s\n' "sway"
  elif pgrep -x gnome-shell >/dev/null 2>&1; then
    printf '%s\n' "gnome"
  elif [[ -n "${WAYLAND_DISPLAY:-}" ]]; then
    printf '%s\n' "wayland"
  else
    printf '%s\n' "unknown"
  fi
}

CURRENT_ENV="$(detect_env)"
SCREENSHOT_BACKEND="$(printf '%s' "$SCREENSHOT_BACKEND" | tr '[:upper:]' '[:lower:]')"

use_niri_backend() {
  case "$SCREENSHOT_BACKEND" in
  niri)
    command -v niri >/dev/null 2>&1
    ;;
  auto)
    [[ "$CURRENT_ENV" == "niri" ]] && command -v niri >/dev/null 2>&1
    ;;
  grim | wlroots | legacy | portable)
    return 1
    ;;
  *)
    return 1
    ;;
  esac
}

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
  wc | window-copy) printf '%s\n' "wc" ;;
  wf | window-save | window-file) printf '%s\n' "wf" ;;
  wi | window-edit | window) printf '%s\n' "wi" ;;
  p | pick | color) printf '%s\n' "p" ;;
  o | open) printf '%s\n' "open" ;;
  d | dir) printf '%s\n' "dir" ;;
  help | -h | --help) printf '%s\n' "help" ;;
  version | -v | --version) printf '%s\n' "version" ;;
  *) printf '%s\n' "$1" ;;
  esac
}

ACTION="$(normalize_action "${1:-ri}")"

is_capture_action() {
  case "$1" in
  rc | rf | ri | rec | sc | sf | si | sec | wc | wf | wi) return 0 ;;
  *) return 1 ;;
  esac
}

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
│             Backend: $SCREENSHOT_BACKEND    │
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
  wc   Window -> clipboard
  wf   Window -> file
  wi   Window -> editor -> file
  p    Pick color
  o    Open latest screenshot
  d    Open screenshot directory

Notes:
- Default action with no args: ri
- Screen actions capture the focused output on MangoWM/Hyprland/Sway/Niri when possible
- Window actions are supported on MangoWM, Hyprland, Sway, and Niri
- Backend selection: SCREENSHOT_BACKEND=auto|niri|grim
- auto uses Niri's native backend only inside a Niri session; grim keeps the
  compositor-independent grim/slurp path elsewhere.
- Active editor: $EDITOR
- Save directory: $SAVE_DIR
EOF

  if [[ "$CURRENT_ENV" == "gnome" ]]; then
    cat <<'EOF'

GNOME mode:
- Capture commands open `gnome-screenshot -i`
- Color picking is not handled by gnome-screenshot in this script
EOF
  fi
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
    require_commands wl-copy || return $?
    if [[ "$CURRENT_ENV" == "hyprland" ]] && command -v hyprpicker >/dev/null 2>&1; then
      return 0
    fi
    require_commands grim slurp || return $?
    if ! command -v magick >/dev/null 2>&1 && ! command -v convert >/dev/null 2>&1; then
      show_notification "Missing dependencies" "Please install: ImageMagick (magick or convert)" "critical"
      return $EXIT_MISSING_DEPENDENCY
    fi
    return 0
    ;;
  esac

  case "$action" in
  rc | sc | wc | rec | sec)
    require_commands wl-copy || return $?
    ;;
  esac

  case "$action" in
  rc | rf | ri | rec)
    if use_niri_backend; then
      require_commands niri || return $?
      return 0
    fi
    require_commands grim slurp || return $?
    ;;
  sc | sf | si | sec)
    if use_niri_backend; then
      require_commands niri jq || return $?
      return 0
    fi
    require_commands grim || return $?
    ;;
  wc | wf | wi)
    if use_niri_backend; then
      require_commands niri jq || return $?
      return 0
    fi
    require_commands grim || return $?
    case "$CURRENT_ENV" in
    hyprland) require_commands hyprctl jq || return $? ;;
    sway) require_commands swaymsg jq || return $? ;;
    niri) require_commands niri jq || return $? ;;
    mango) require_commands mmsg || return $? ;;
    *)
      show_notification "Unsupported" "Window capture is not supported in this environment" "critical"
      return $EXIT_UNSUPPORTED
      ;;
    esac
    ;;
  esac

  case "$action" in
  ri | rec | si | sec | wi)
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
  "$EXIT_UNSUPPORTED")
    show_notification "Unsupported" "$label is not supported in this environment" "critical"
    ;;
  "$EXIT_MISSING_DEPENDENCY") ;;
  *)
    show_notification "Screenshot" "$label failed" "critical"
    ;;
  esac

  return "$status"
}

handle_gnome_capture() {
  if command -v gnome-screenshot >/dev/null 2>&1; then
    gnome-screenshot -i
    return $EXIT_SUCCESS
  fi

  show_notification "Missing dependencies" "Please install gnome-screenshot" "critical"
  return $EXIT_MISSING_DEPENDENCY
}

focused_output_name() {
  local output=""

  case "$CURRENT_ENV" in
  hyprland)
    if command -v hyprctl >/dev/null 2>&1 && command -v jq >/dev/null 2>&1; then
      output="$(hyprctl monitors -j 2>/dev/null | jq -r '.[] | select(.focused == true) | .name // empty' | head -n1 || true)"
    fi
    ;;
  sway)
    if command -v swaymsg >/dev/null 2>&1 && command -v jq >/dev/null 2>&1; then
      output="$(swaymsg -t get_outputs 2>/dev/null | jq -r '.[] | select(.focused == true) | .name // empty' | head -n1 || true)"
    fi
    ;;
  niri)
    if command -v niri >/dev/null 2>&1 && command -v jq >/dev/null 2>&1; then
      output="$(niri msg -j focused-output 2>/dev/null | jq -r '.name // empty' | head -n1 || true)"
    fi
    ;;
  mango)
    if command -v mmsg >/dev/null 2>&1; then
      output="$(mmsg -g -o 2>/dev/null | awk '$2 == "selmon" && $3 == "1" { print $1; exit }' || true)"
    fi
    ;;
  esac

  printf '%s\n' "$output"
}

focused_window_geometry() {
  local info x y w h monitor

  case "$CURRENT_ENV" in
  hyprland)
    info="$(hyprctl activewindow -j 2>/dev/null || true)"
    [[ -n "$info" ]] || return 1
    x="$(jq -r '.at[0] // empty' <<<"$info" 2>/dev/null | head -n1)"
    y="$(jq -r '.at[1] // empty' <<<"$info" 2>/dev/null | head -n1)"
    w="$(jq -r '.size[0] // empty' <<<"$info" 2>/dev/null | head -n1)"
    h="$(jq -r '.size[1] // empty' <<<"$info" 2>/dev/null | head -n1)"
    ;;
  sway)
    info="$(swaymsg -t get_tree 2>/dev/null || true)"
    [[ -n "$info" ]] || return 1
    x="$(jq -r '.. | select(.focused? == true) | .rect.x // empty' <<<"$info" 2>/dev/null | head -n1)"
    y="$(jq -r '.. | select(.focused? == true) | .rect.y // empty' <<<"$info" 2>/dev/null | head -n1)"
    w="$(jq -r '.. | select(.focused? == true) | .rect.width // empty' <<<"$info" 2>/dev/null | head -n1)"
    h="$(jq -r '.. | select(.focused? == true) | .rect.height // empty' <<<"$info" 2>/dev/null | head -n1)"
    ;;
  niri)
    info="$(niri msg -j focused-window 2>/dev/null || true)"
    [[ -n "$info" ]] || return 1
    x="$(jq -r '.workspace_view_position.x? // empty' <<<"$info" 2>/dev/null | head -n1)"
    y="$(jq -r '.workspace_view_position.y? // empty' <<<"$info" 2>/dev/null | head -n1)"
    w="$(jq -r '.window_size.width? // empty' <<<"$info" 2>/dev/null | head -n1)"
    h="$(jq -r '.window_size.height? // empty' <<<"$info" 2>/dev/null | head -n1)"
    ;;
  mango)
    info="$(mmsg -g -x 2>/dev/null || true)"
    [[ -n "$info" ]] || return 1
    monitor="$(focused_output_name 2>/dev/null || true)"
    if [[ -n "$monitor" ]]; then
      x="$(awk -v monitor="$monitor" '$1 == monitor && $2 == "x" { print $3; exit }' <<<"$info")"
      y="$(awk -v monitor="$monitor" '$1 == monitor && $2 == "y" { print $3; exit }' <<<"$info")"
      w="$(awk -v monitor="$monitor" '$1 == monitor && $2 == "width" { print $3; exit }' <<<"$info")"
      h="$(awk -v monitor="$monitor" '$1 == monitor && $2 == "height" { print $3; exit }' <<<"$info")"
    fi
    if [[ -z "${x:-}" || -z "${y:-}" || -z "${w:-}" || -z "${h:-}" ]]; then
      x="$(awk '$2 == "x" { print $3; exit }' <<<"$info")"
      y="$(awk '$2 == "y" { print $3; exit }' <<<"$info")"
      w="$(awk '$2 == "width" { print $3; exit }' <<<"$info")"
      h="$(awk '$2 == "height" { print $3; exit }' <<<"$info")"
    fi
    ;;
  *)
    return 1
    ;;
  esac

  [[ -n "$x" && -n "$y" && -n "$w" && -n "$h" ]] || return 1
  printf '%s,%s %sx%s\n' "$x" "$y" "$w" "$h"
}

absolute_path() {
  local path="$1"
  case "$path" in
  /*) printf '%s\n' "$path" ;;
  *) printf '%s/%s\n' "$PWD" "$path" ;;
  esac
}

normalize_boolean() {
  case "${1:-false}" in
  1 | true | TRUE | yes | YES | on | ON) printf '%s\n' "true" ;;
  *) printf '%s\n' "false" ;;
  esac
}

niri_wait_for_screenshot_file() {
  local filename="$1"
  local timeout="$NIRI_UI_TIMEOUT"
  local ticks

  [[ "$timeout" =~ ^[0-9]+$ ]] || timeout=120
  ticks=$((timeout * 10))

  while ((ticks > 0)); do
    [[ -s "$filename" ]] && return "$EXIT_SUCCESS"
    sleep 0.1
    ticks=$((ticks - 1))
  done

  return "$EXIT_CANCELLED"
}

niri_focused_window_needs_interactive_capture() {
  local info app_id title

  command -v niri >/dev/null 2>&1 || return 1
  command -v jq >/dev/null 2>&1 || return 1

  info="$(niri msg -j focused-window 2>/dev/null || true)"
  [[ -n "$info" && "$info" != "null" ]] || return 1

  app_id="$(jq -r '.app_id // .class // ""' <<<"$info" 2>/dev/null || true)"
  title="$(jq -r '.title // ""' <<<"$info" 2>/dev/null || true)"

  if [[ "$app_id" =~ ^(discord|WebCord|ferdium|Ferdium|org\.telegram\.desktop|Signal|Slack)$ ]]; then
    return 0
  fi

  if [[ "$app_id" =~ ^(org\.keepassxc\.KeePassXC|KeePassXC|com\.bitwarden\.desktop|Bitwarden|com\.1password\.1Password|1Password|io\.ente\.auth|org\.gnome\.World\.Secrets|org\.gnome\.seahorse\.Application|seahorse|kwalletmanager5|kwalletmanager|pinentry.*|gcr-prompter|polkit-gnome-authentication-agent-1|clipse|copyq)$ ]]; then
    return 0
  fi

  if [[ "$title" =~ [Pp]assword|[Pp]assphrase|[Aa]uthentication|[Uu]nlock|[Ss]ecret|[Tt]wo-[Ff]actor|[Vv]erification[[:space:]]+[Cc]ode|[Oo]ne-[Tt]ime|OTP|otp ]]; then
    return 0
  fi

  if [[ "$app_id" =~ ^(firefox|librewolf|zen|brave.*|chromium|google-chrome.*|microsoft-edge.*|helium.*)$ ]] &&
    [[ "$title" =~ [Pp]rivate[[:space:]]+[Bb]rowsing|[Pp]rivate[[:space:]]+[Ww]indow|[Ii]ncognito|[Ii]n[Pp]rivate ]]; then
    return 0
  fi

  return 1
}

take_niri_interactive_screenshot() {
  local filename
  filename="$(absolute_path "$1")"
  mkdir -p "$(dirname "$filename")"
  rm -f "$filename"

  niri msg action screenshot \
    --show-pointer "$(normalize_boolean "$NIRI_REGION_SHOW_POINTER")" \
    --path "$filename" >/dev/null

  niri_wait_for_screenshot_file "$filename"
}

take_niri_screen_screenshot() {
  local filename
  filename="$(absolute_path "$1")"
  mkdir -p "$(dirname "$filename")"
  rm -f "$filename"

  if niri_focused_window_needs_interactive_capture; then
    take_niri_interactive_screenshot "$filename"
    return $?
  fi

  if niri msg action screenshot-screen \
    --show-pointer "$(normalize_boolean "$NIRI_SCREEN_SHOW_POINTER")" \
    --path "$filename" >/dev/null && [[ -s "$filename" ]]; then
    return "$EXIT_SUCCESS"
  fi

  take_niri_interactive_screenshot "$filename"
}

take_niri_window_screenshot() {
  local filename
  filename="$(absolute_path "$1")"
  mkdir -p "$(dirname "$filename")"
  rm -f "$filename"

  if niri_focused_window_needs_interactive_capture; then
    take_niri_interactive_screenshot "$filename"
    return $?
  fi

  if niri msg action screenshot-window \
    --show-pointer "$(normalize_boolean "$NIRI_WINDOW_SHOW_POINTER")" \
    --path "$filename" >/dev/null && [[ -s "$filename" ]]; then
    return "$EXIT_SUCCESS"
  fi

  take_niri_interactive_screenshot "$filename"
}

take_region_screenshot() {
  local filename="$1"
  local geometry

  if use_niri_backend; then
    take_niri_interactive_screenshot "$filename"
    return $?
  fi

  geometry="$(slurp -b "$SLURP_BACKGROUND" -c "$SLURP_BORDER" -s "$SLURP_SELECTION" -w "$SLURP_BORDER_WIDTH" 2>/dev/null || true)"
  [[ -n "$geometry" ]] || return "$EXIT_CANCELLED"

  grim -g "$geometry" "$filename"
}

take_screen_screenshot() {
  local filename="$1"
  local output_name

  if use_niri_backend; then
    take_niri_screen_screenshot "$filename"
    return $?
  fi

  output_name="$(focused_output_name)"
  if [[ -n "$output_name" && "$output_name" != "null" ]]; then
    grim -o "$output_name" "$filename"
  else
    grim "$filename"
  fi
}

take_window_screenshot() {
  local filename="$1"
  local geometry

  if use_niri_backend; then
    take_niri_window_screenshot "$filename"
    return $?
  fi

  geometry="$(focused_window_geometry 2>/dev/null || true)"
  [[ -n "$geometry" ]] || return "$EXIT_UNSUPPORTED"

  grim -g "$geometry" "$filename"
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

  if [[ "$CURRENT_ENV" == "hyprland" ]] && command -v hyprpicker >/dev/null 2>&1; then
    color="$(hyprpicker -q -f hex -l 2>/dev/null || true)"
    [[ -n "$color" ]] || return $EXIT_CANCELLED
    printf '%s\n' "$color"
    return 0
  fi

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

if [[ "$CURRENT_ENV" == "gnome" ]] && is_capture_action "$ACTION"; then
  handle_gnome_capture
  exit $?
fi

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
wc) run_capture_flow take_window_screenshot copy "Window screenshot" ;;
wf) run_capture_flow take_window_screenshot save "Window screenshot" ;;
wi) run_capture_flow take_window_screenshot edit "Window screenshot" ;;
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
