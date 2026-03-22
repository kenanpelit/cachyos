#!/usr/bin/env bash
# ==============================================================================
# Script: osc-media.sh
# Description: Smart media controller that routes commands to the best available
#              player (Spotify, VLC, MPV, MPD, Browsers, etc.) or a specific
#              player if requested.
# Usage: osc-media.sh [player] <command>
#        osc-media.sh <command>
# ==============================================================================

set -Eeuo pipefail

NOTIFY_TIMEOUT="${NOTIFY_TIMEOUT:-3200}"
SYNC_ID="x-canonical-private-synchronous:osc-media"
MPV_SOCKET="${MPV_SOCKET:-/tmp/mpvsocket}"
SPOTIFY_START_TIMEOUT="${SPOTIFY_START_TIMEOUT:-12}"
STATE_ROOT="${XDG_RUNTIME_DIR:-}"
if [[ -z "$STATE_ROOT" || ! -d "$STATE_ROOT" || ! -w "$STATE_ROOT" ]]; then
  STATE_ROOT="/tmp"
fi
LAST_PLAYER_FILE="${STATE_ROOT}/osc-media-last-player"
MAX_FIELD_LENGTH=96

TARGET_PLAYER=""
COMMAND=""
LAST_PLAYER_ID=""
ACTION_LABEL=""

ACTIVE_PLAYER_KIND=""
ACTIVE_PLAYER_NAME=""
ACTIVE_STATUS=""
MEDIA_TITLE=""
MEDIA_ARTIST=""
MEDIA_ALBUM=""
MEDIA_ART_URL=""

show_help() {
  cat <<'EOF'
HyprFlow Media Controller

Usage:
  osc-media.sh [PLAYER] <COMMAND>
  osc-media.sh <COMMAND>

Commands:
  toggle       Play/Pause toggle
  play         Play
  pause        Pause
  stop         Stop
  next         Next track
  prev         Previous track
  status       Show current player status

Target players:
  spotify      Target Spotify explicitly
  vlc          Target VLC explicitly
  mpv          Target MPV explicitly (IPC socket)
  mpd / mpc    Target MPD explicitly
  browser      Target browser-based MPRIS players
  <empty>      Auto-detect the best active player
EOF
  exit 0
}

have_cmd() {
  command -v "$1" >/dev/null 2>&1
}

clean_text() {
  local value="${1:-}"
  printf '%s' "$value" \
    | tr '\r' ' ' \
    | sed ':a;N;$!ba;s/\n/, /g; s/[[:space:]]\+/ /g; s/^ //; s/ $//'
}

truncate_text() {
  local text
  local max_len="${2:-$MAX_FIELD_LENGTH}"

  text="$(clean_text "${1:-}")"
  if (( ${#text} > max_len )); then
    printf '%s...\n' "${text:0:max_len}"
  else
    printf '%s\n' "$text"
  fi
}

normalize_status() {
  case "${1:-}" in
    Playing|playing) printf 'Playing\n' ;;
    Paused|paused) printf 'Paused\n' ;;
    Stopped|stopped) printf 'Stopped\n' ;;
    *) printf 'Unknown\n' ;;
  esac
}

status_label() {
  case "${1:-Unknown}" in
    Playing) printf 'Oynatiliyor\n' ;;
    Paused) printf 'Duraklatildi\n' ;;
    Stopped) printf 'Durduruldu\n' ;;
    *) printf 'Hazir\n' ;;
  esac
}

command_label() {
  case "${1:-}" in
    toggle) printf 'Play/Pause\n' ;;
    play) printf 'Oynat\n' ;;
    pause) printf 'Duraklat\n' ;;
    next) printf 'Sonraki parca\n' ;;
    prev|previous) printf 'Onceki parca\n' ;;
    stop) printf 'Durdur\n' ;;
    status) printf 'Durum\n' ;;
    *) printf 'Medya kontrolu\n' ;;
  esac
}

player_is_browser() {
  case "${1,,}" in
    *firefox*|*chromium*|*chrome*|*brave*|*zen*|*vivaldi*|*edge*)
      return 0
      ;;
  esac
  return 1
}

player_pretty_name() {
  local name="${1:-unknown}"
  local lower="${name,,}"

  case "$lower" in
    spotify*) printf 'Spotify\n' ;;
    vlc*) printf 'VLC\n' ;;
    mpv*) printf 'MPV\n' ;;
    mpd) printf 'MPD\n' ;;
    firefox*) printf 'Firefox\n' ;;
    chromium*) printf 'Chromium\n' ;;
    chrome*) printf 'Chrome\n' ;;
    brave*) printf 'Brave\n' ;;
    zen*) printf 'Zen\n' ;;
    vivaldi*) printf 'Vivaldi\n' ;;
    edge*) printf 'Edge\n' ;;
    *)
      printf '%s\n' "$name" \
        | awk -F'.' '{print $1}' \
        | tr '_-' '  ' \
        | awk '{for (i=1; i<=NF; ++i) $i=toupper(substr($i,1,1)) substr($i,2); print}'
      ;;
  esac
}

player_icon() {
  local lower="${1,,}"

  case "$lower" in
    spotify*)
      if [[ -f /usr/share/icons/hicolor/256x256/apps/spotify.png ]]; then
        printf '/usr/share/icons/hicolor/256x256/apps/spotify.png\n'
      else
        printf 'spotify\n'
      fi
      ;;
    vlc*) printf 'vlc\n' ;;
    mpv*) printf 'mpv\n' ;;
    mpd) printf 'audio-x-generic\n' ;;
    firefox*) printf 'firefox\n' ;;
    chromium*|chrome*) printf 'chromium\n' ;;
    brave*) printf 'brave-browser\n' ;;
    zen*) printf 'browser\n' ;;
    vivaldi*) printf 'vivaldi\n' ;;
    edge*) printf 'microsoft-edge\n' ;;
    *) printf 'audio-x-generic\n' ;;
  esac
}

resolve_notification_icon() {
  local art="${MEDIA_ART_URL:-}"

  case "$art" in
    file://*)
      art="${art#file://}"
      art="${art//%20/ }"
      ;;
    /*)
      ;;
    *)
      art=""
      ;;
  esac

  if [[ -n "$art" && -f "$art" ]]; then
    printf '%s\n' "$art"
    return 0
  fi

  player_icon "$ACTIVE_PLAYER_NAME"
}

notify_media() {
  local title="$1"
  local body="$2"
  local icon="${3:-audio-x-generic}"
  local urgency="${4:-normal}"
  local timeout="${5:-$NOTIFY_TIMEOUT}"

  [[ -n "$body" ]] || body="Bilgi yok"

  if have_cmd notify-send; then
    notify-send \
      -a "osc-media" \
      -u "$urgency" \
      -t "$timeout" \
      -h string:"$SYNC_ID" \
      -i "$icon" \
      "$title" \
      "$body" >/dev/null 2>&1 || true
  else
    printf '%s\n%s\n' "$title" "$body"
  fi
}

fail() {
  local title="${1:-Medya kontrolu}"
  local body="${2:-Bilinmeyen hata}"
  notify_media "$title" "$body" "dialog-error" "critical" 4200
  printf 'osc-media: %s\n' "$body" >&2
  exit 1
}

read_last_player() {
  if [[ -r "$LAST_PLAYER_FILE" ]]; then
    head -n1 "$LAST_PLAYER_FILE" 2>/dev/null | tr -d '\r'
  fi
}

write_last_player() {
  local player_id="${1:-}"
  [[ -n "$player_id" ]] || return 0
  [[ -d "$STATE_ROOT" && -w "$STATE_ROOT" ]] || return 0
  printf '%s\n' "$player_id" >"$LAST_PLAYER_FILE" 2>/dev/null || true
}

spotify_process_running() {
  pgrep -x spotify >/dev/null 2>&1 && return 0

  pgrep -af '[s]potify' 2>/dev/null | awk '
    {
      cmd=$2
      sub(/^.*\//, "", cmd)
      if (cmd == "spotify") {
        found=1
        exit
      }
    }
    END { exit(found ? 0 : 1) }
  '
}

spotify_should_autostart() {
  [[ "$TARGET_PLAYER" == "spotify" ]] || return 1

  case "$COMMAND" in
    toggle|play|next|prev|previous|status)
      return 0
      ;;
  esac

  return 1
}

wait_for_target_player() {
  local target="$1"
  local timeout="${2:-$SPOTIFY_START_TIMEOUT}"
  local attempt=""
  local elapsed=0

  while (( elapsed < timeout * 4 )); do
    attempt="$(pick_best_mpris_for_target "$target")"
    if [[ "$attempt" != none:* ]]; then
      printf '%s\n' "$attempt"
      return 0
    fi
    sleep 0.25
    elapsed=$((elapsed + 1))
  done

  printf 'none:%s\n' "$target"
}

ensure_spotify_target_ready() {
  local resolved=""

  resolved="$(pick_best_mpris_for_target "spotify")"
  if [[ "$resolved" != none:* ]]; then
    printf '%s\n' "$resolved"
    return 0
  fi

  spotify_should_autostart || {
    printf '%s\n' "$resolved"
    return 0
  }

  have_cmd spotify || {
    printf 'none:spotify\n'
    return 0
  }

  if ! spotify_process_running; then
    notify_media \
      "Spotify · Baslatiliyor" \
      "Spotify aciliyor, hazir olunca komut gonderilecek." \
      "$(player_icon "spotify")" \
      "normal" \
      2600
    spotify >/dev/null 2>&1 &
    disown || true
  fi

  wait_for_target_player "spotify" "$SPOTIFY_START_TIMEOUT"
}

list_mpris_players() {
  have_cmd playerctl || return 0
  playerctl -l 2>/dev/null | awk '
    NF && $0 != "playerctld" && !seen[$0]++ { print }
  '
}

mpris_status() {
  have_cmd playerctl || {
    printf 'Unknown\n'
    return 0
  }
  normalize_status "$(playerctl -p "$1" status 2>/dev/null || true)"
}

mpd_available() {
  have_cmd mpc && mpc status >/dev/null 2>&1
}

mpd_status() {
  mpd_available || {
    printf 'Unknown\n'
    return 0
  }

  local state
  state="$(mpc status 2>/dev/null | grep -o '\[[^]]*\]' | tr -d '[]' | head -n1 || true)"
  normalize_status "$state"
}

mpv_socket_ready() {
  [[ -S "$MPV_SOCKET" ]] && have_cmd socat
}

mpv_raw() {
  local payload="$1"
  mpv_socket_ready || return 1
  printf '%s\n' "$payload" | socat - "$MPV_SOCKET" 2>/dev/null
}

json_data_from_response() {
  local response="${1:-}"

  if have_cmd jq; then
    jq -r '
      if .data == null then ""
      elif .data == true then "true"
      elif .data == false then "false"
      else .data
      end
    ' <<<"$response" 2>/dev/null
    return 0
  fi

  if grep -q '"data":true' <<<"$response"; then
    printf 'true\n'
    return 0
  fi
  if grep -q '"data":false' <<<"$response"; then
    printf 'false\n'
    return 0
  fi
  sed -n 's/.*"data":"\([^"]*\)".*/\1/p' <<<"$response" | head -n1
}

mpv_get_prop() {
  local prop="$1"
  local response=""

  response="$(mpv_raw "{\"command\":[\"get_property\",\"$prop\"]}")" || return 1
  json_data_from_response "$response"
}

mpv_status() {
  mpv_socket_ready || {
    printf 'Unknown\n'
    return 0
  }

  local idle paused
  idle="$(mpv_get_prop "idle-active" || true)"
  if [[ "$idle" == "true" ]]; then
    printf 'Stopped\n'
    return 0
  fi

  paused="$(mpv_get_prop "pause" || true)"
  if [[ "$paused" == "true" ]]; then
    printf 'Paused\n'
  else
    printf 'Playing\n'
  fi
}

candidate_score() {
  local kind="$1"
  local name="$2"
  local status="$3"
  local score=0
  local lower="${name,,}"

  case "$status" in
    Playing) score=300 ;;
    Paused) score=180 ;;
    Stopped) score=40 ;;
    *) score=20 ;;
  esac

  case "$kind" in
    mpv|mpd)
      score=$((score + 40))
      ;;
    mpris)
      if player_is_browser "$name"; then
        score=$((score + 8))
      else
        score=$((score + 35))
      fi
      ;;
  esac

  case "$lower" in
    spotify*) score=$((score + 35)) ;;
    vlc*) score=$((score + 28)) ;;
    mpv*) score=$((score + 24)) ;;
    firefox*|chromium*|chrome*|brave*|zen*|vivaldi*|edge*) score=$((score + 10)) ;;
  esac

  if [[ "${kind}:${name}" == "$LAST_PLAYER_ID" ]]; then
    score=$((score + 90))
  fi

  case "$COMMAND" in
    toggle|play|pause|next|prev|previous|status)
      [[ "$status" == "Playing" ]] && score=$((score + 18))
      ;;
  esac

  if [[ "$COMMAND" == "play" && "$status" == "Paused" ]]; then
    score=$((score + 15))
  fi

  printf '%s\n' "$score"
}

pick_best_mpris_for_target() {
  local target="$1"
  local best_score=-1
  local best_player=""
  local player=""
  local status=""
  local score=0

  while IFS= read -r player; do
    [[ -n "$player" ]] || continue

    case "$target" in
      browser)
        player_is_browser "$player" || continue
        ;;
      *)
        [[ "${player,,}" == *"${target,,}"* ]] || continue
        ;;
    esac

    status="$(mpris_status "$player")"
    score="$(candidate_score "mpris" "$player" "$status")"
    if (( score > best_score )); then
      best_score="$score"
      best_player="$player"
    fi
  done < <(list_mpris_players)

  if [[ -n "$best_player" ]]; then
    printf 'mpris:%s\n' "$best_player"
  else
    printf 'none:%s\n' "$target"
  fi
}

resolve_explicit_target() {
  case "$TARGET_PLAYER" in
    mpd)
      if mpd_available; then
        printf 'mpd:mpd\n'
      else
        printf 'none:mpd\n'
      fi
      ;;
    mpv)
      if [[ -S "$MPV_SOCKET" ]] || pgrep -x mpv >/dev/null 2>&1; then
        printf 'mpv:mpv\n'
      else
        printf 'none:mpv\n'
      fi
      ;;
    spotify)
      ensure_spotify_target_ready
      ;;
    vlc|browser)
      pick_best_mpris_for_target "$TARGET_PLAYER"
      ;;
    *)
      pick_best_mpris_for_target "$TARGET_PLAYER"
      ;;
  esac
}

get_active_player_type() {
  if [[ -n "$TARGET_PLAYER" ]]; then
    resolve_explicit_target
    return 0
  fi

  local best_score=-1
  local best_kind="none"
  local best_name="none"
  local player=""
  local status=""
  local score=0

  if mpv_socket_ready; then
    status="$(mpv_status)"
    score="$(candidate_score "mpv" "mpv" "$status")"
    if (( score > best_score )); then
      best_score="$score"
      best_kind="mpv"
      best_name="mpv"
    fi
  fi

  if mpd_available; then
    status="$(mpd_status)"
    score="$(candidate_score "mpd" "mpd" "$status")"
    if (( score > best_score )); then
      best_score="$score"
      best_kind="mpd"
      best_name="mpd"
    fi
  fi

  while IFS= read -r player; do
    [[ -n "$player" ]] || continue
    status="$(mpris_status "$player")"
    score="$(candidate_score "mpris" "$player" "$status")"
    if (( score > best_score )); then
      best_score="$score"
      best_kind="mpris"
      best_name="$player"
    fi
  done < <(list_mpris_players)

  printf '%s:%s\n' "$best_kind" "$best_name"
}

load_mpris_metadata() {
  local player="$1"
  local url=""

  MEDIA_TITLE="$(truncate_text "$(playerctl -p "$player" metadata title 2>/dev/null || true)")"
  MEDIA_ARTIST="$(truncate_text "$(playerctl -p "$player" metadata artist 2>/dev/null || true)")"
  MEDIA_ALBUM="$(truncate_text "$(playerctl -p "$player" metadata album 2>/dev/null || true)")"
  MEDIA_ART_URL="$(clean_text "$(playerctl -p "$player" metadata mpris:artUrl 2>/dev/null || true)")"

  if [[ -z "$MEDIA_TITLE" ]]; then
    url="$(playerctl -p "$player" metadata xesam:url 2>/dev/null || true)"
    if [[ -n "$url" ]]; then
      MEDIA_TITLE="$(truncate_text "$(basename "${url%%\?*}" | sed 's/%20/ /g')")"
    fi
  fi

  [[ -n "$MEDIA_TITLE" ]] || MEDIA_TITLE="Bilinmeyen parca"
}

load_mpd_metadata() {
  local current_file=""

  MEDIA_TITLE="$(truncate_text "$(mpc current -f '%title%' 2>/dev/null || true)")"
  MEDIA_ARTIST="$(truncate_text "$(mpc current -f '%artist%' 2>/dev/null || true)")"
  MEDIA_ALBUM="$(truncate_text "$(mpc current -f '%album%' 2>/dev/null || true)")"
  MEDIA_ART_URL=""

  if [[ -z "$MEDIA_TITLE" ]]; then
    current_file="$(mpc current -f '%file%' 2>/dev/null || true)"
    if [[ -n "$current_file" ]]; then
      MEDIA_TITLE="$(truncate_text "$(basename "$current_file")")"
    fi
  fi

  [[ -n "$MEDIA_TITLE" ]] || MEDIA_TITLE="MPD hazir"
}

load_mpv_metadata() {
  local path=""

  MEDIA_TITLE="$(truncate_text "$(mpv_get_prop "media-title" || true)")"
  MEDIA_ARTIST="$(truncate_text "$(mpv_get_prop "metadata/by-key/Artist" || true)")"
  MEDIA_ALBUM="$(truncate_text "$(mpv_get_prop "metadata/by-key/Album" || true)")"
  MEDIA_ART_URL=""

  if [[ -z "$MEDIA_TITLE" ]]; then
    path="$(mpv_get_prop "path" || true)"
    if [[ -n "$path" ]]; then
      MEDIA_TITLE="$(truncate_text "$(basename "${path%%\?*}")")"
    fi
  fi

  if [[ "$ACTIVE_STATUS" == "Stopped" && -z "$MEDIA_TITLE" ]]; then
    MEDIA_TITLE="MPV hazir"
  fi

  [[ -n "$MEDIA_TITLE" ]] || MEDIA_TITLE="Bilinmeyen parca"
}

load_current_metadata() {
  MEDIA_TITLE=""
  MEDIA_ARTIST=""
  MEDIA_ALBUM=""
  MEDIA_ART_URL=""

  case "$ACTIVE_PLAYER_KIND" in
    mpris) load_mpris_metadata "$ACTIVE_PLAYER_NAME" ;;
    mpd) load_mpd_metadata ;;
    mpv) load_mpv_metadata ;;
  esac
}

read_current_status() {
  case "$ACTIVE_PLAYER_KIND" in
    mpris) ACTIVE_STATUS="$(mpris_status "$ACTIVE_PLAYER_NAME")" ;;
    mpd) ACTIVE_STATUS="$(mpd_status)" ;;
    mpv) ACTIVE_STATUS="$(mpv_status)" ;;
    *) ACTIVE_STATUS="Unknown" ;;
  esac
}

execute_mpris_command() {
  local action="$COMMAND"

  case "$COMMAND" in
    toggle) action="play-pause" ;;
    prev) action="previous" ;;
    previous) action="previous" ;;
    status) return 0 ;;
  esac

  playerctl -p "$ACTIVE_PLAYER_NAME" "$action" >/dev/null 2>&1
}

execute_mpd_command() {
  case "$COMMAND" in
    toggle) mpc toggle >/dev/null 2>&1 ;;
    play) mpc play >/dev/null 2>&1 ;;
    pause) mpc pause >/dev/null 2>&1 ;;
    next) mpc next >/dev/null 2>&1 ;;
    prev|previous) mpc prev >/dev/null 2>&1 ;;
    stop) mpc stop >/dev/null 2>&1 ;;
    status) return 0 ;;
    *) return 1 ;;
  esac
}

execute_mpv_command() {
  local payload=""

  mpv_socket_ready || fail "MPV kontrolu" "MPV IPC soketi bulunamadi: $MPV_SOCKET"

  case "$COMMAND" in
    toggle) payload='{"command":["cycle","pause"]}' ;;
    play) payload='{"command":["set_property","pause",false]}' ;;
    pause) payload='{"command":["set_property","pause",true]}' ;;
    next) payload='{"command":["playlist-next"]}' ;;
    prev|previous) payload='{"command":["playlist-prev"]}' ;;
    stop) payload='{"command":["stop"]}' ;;
    status) return 0 ;;
    *) return 1 ;;
  esac

  mpv_raw "$payload" >/dev/null
}

execute_active_command() {
  case "$ACTIVE_PLAYER_KIND" in
    mpris) execute_mpris_command ;;
    mpd) execute_mpd_command ;;
    mpv) execute_mpv_command ;;
    *) return 1 ;;
  esac
}

build_notification_body() {
  local body=""

  body="Durum: $(status_label "$ACTIVE_STATUS")"
  [[ -n "$MEDIA_TITLE" ]] && body="${body}\nParca: ${MEDIA_TITLE}"
  [[ -n "$MEDIA_ARTIST" ]] && body="${body}\nSanatci: ${MEDIA_ARTIST}"
  [[ -n "$MEDIA_ALBUM" ]] && body="${body}\nAlbum: ${MEDIA_ALBUM}"
  printf '%s\n' "$body"
}

send_player_notification() {
  local pretty_name
  local title
  local icon

  pretty_name="$(player_pretty_name "$ACTIVE_PLAYER_NAME")"
  icon="$(resolve_notification_icon)"

  if [[ "$COMMAND" == "status" ]]; then
    title="${pretty_name} · $(status_label "$ACTIVE_STATUS")"
  else
    title="${pretty_name} · ${ACTION_LABEL}"
  fi

  notify_media "$title" "$(build_notification_body)" "$icon"
}

print_terminal_summary() {
  [[ -t 1 ]] || return 0

  printf 'Player: %s\n' "$(player_pretty_name "$ACTIVE_PLAYER_NAME")"
  printf 'Status: %s\n' "$(status_label "$ACTIVE_STATUS")"
  printf 'Title: %s\n' "${MEDIA_TITLE:-Bilgi yok}"
  [[ -n "$MEDIA_ARTIST" ]] && printf 'Artist: %s\n' "$MEDIA_ARTIST"
  [[ -n "$MEDIA_ALBUM" ]] && printf 'Album: %s\n' "$MEDIA_ALBUM"
}

if [[ $# -eq 0 || "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  show_help
fi

case "${1,,}" in
  spotify|vlc|mpv|mpd|mpc|browser)
    TARGET_PLAYER="${1,,}"
    COMMAND="${2:-toggle}"
    [[ "$TARGET_PLAYER" == "mpc" ]] && TARGET_PLAYER="mpd"
    ;;
  toggle|play|pause|next|prev|previous|stop|status)
    COMMAND="${1,,}"
    ;;
  *)
    printf 'Error: Unknown command or player: %s\n' "${1:-}" >&2
    show_help
    ;;
esac

case "${COMMAND,,}" in
  toggle|play|pause|next|prev|previous|stop|status)
    COMMAND="${COMMAND,,}"
    ;;
  *)
    fail "Medya kontrolu" "Gecersiz komut: $COMMAND"
    ;;
esac

ACTION_LABEL="$(command_label "$COMMAND")"
LAST_PLAYER_ID="$(read_last_player)"

ACTIVE_INFO="$(get_active_player_type)"
ACTIVE_PLAYER_KIND="${ACTIVE_INFO%%:*}"
ACTIVE_PLAYER_NAME="${ACTIVE_INFO##*:}"

if [[ "$ACTIVE_PLAYER_KIND" == "none" ]]; then
  if [[ "$ACTIVE_PLAYER_NAME" == "none" ]]; then
    fail "Medya kontrolu" "Kontrol edilebilir bir medya oynatici bulunamadi."
  fi
  fail "Medya kontrolu" "${ACTIVE_PLAYER_NAME} icin kontrol edilebilir bir oynatici bulunamadi."
fi

if [[ "$COMMAND" != "status" ]]; then
  if ! execute_active_command; then
    fail "Medya kontrolu" "$(player_pretty_name "$ACTIVE_PLAYER_NAME") icin '$COMMAND' komutu basarisiz oldu."
  fi
  sleep 0.15
fi

read_current_status
load_current_metadata
write_last_player "${ACTIVE_PLAYER_KIND}:${ACTIVE_PLAYER_NAME}"
send_player_notification
print_terminal_summary

exit 0
