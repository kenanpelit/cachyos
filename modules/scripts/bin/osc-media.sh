#!/usr/bin/env bash
# ==============================================================================
# Script: osc-media.sh
# Description: Smart media controller that routes commands to the active player
#              (VLC, Spotify, MPV, MPD, Browsers, etc.) or a specific player if requested.
# Usage: osc-media.sh [player] <command>
#        osc-media.sh <command> (auto-detects active player)
# ==============================================================================

# Notifications config
NOTIFY_TIMEOUT=3000
SYNC_ID="x-canonical-private-synchronous:osc-media"
MPV_SOCKET="/tmp/mpvsocket"

# Icons
ICON_PLAY="▶️"
ICON_PAUSE="⏸️"
ICON_STOP="⏹️"
ICON_NEXT="⏭️"
ICON_PREV="⏮️"
ICON_NOTE="🎵"

# Helper to show help menu
show_help() {
  echo -e "\033[0;34mHyprFlow Media Controller\033[0m"
  echo "Usage: $(basename "$0") [PLAYER] <COMMAND>"
  echo ""
  echo -e "\033[1;33mCommands (COMMAND):\033[0m"
  echo "  toggle       Play/Pause toggle"
  echo "  play         Play"
  echo "  pause        Pause"
  echo "  stop         Stop"
  echo "  next         Next track"
  echo "  prev         Previous track"
  echo "  status       Show current status"
  echo ""
  echo -e "\033[1;33mTarget Players (PLAYER, optional):\033[0m"
  echo "  spotify      Target Spotify explicitly"
  echo "  vlc          Target VLC explicitly"
  echo "  mpv          Target MPV explicitly (via IPC)"
  echo "  mpd / mpc    Target MPD explicitly"
  echo "  browser      Target browsers (Brave, Chrome, Firefox)"
  echo "  <empty>      Auto-detect active player"
  echo ""
  echo "Examples:"
  echo "  $(basename "$0") toggle"
  echo "  $(basename "$0") spotify next"
  echo "  $(basename "$0") mpv pause"
  exit 0
}

if [[ -z "$1" || "$1" == "--help" || "$1" == "-h" ]]; then
  show_help
fi

# 1. Parse arguments (check if first arg is a specific player)
TARGET_PLAYER=""
COMMAND=""

case "$1" in
spotify | vlc | mpv | mpd | mpc | browser)
  TARGET_PLAYER="$1"
  COMMAND="${2:-toggle}"
  [ "$TARGET_PLAYER" = "mpc" ] && TARGET_PLAYER="mpd" # normalize mpc to mpd
  ;;
toggle | play | pause | next | prev | previous | stop | status)
  COMMAND="$1"
  ;;
*)
  echo "Error: Unknown command '$1'"
  show_help
  ;;
esac

# 2. Helper to send notification
notify_media() {
  local title="$1"
  local body="$2"
  local icon_path="${3:-audio-headphones}"

  # Strip path parameters and use base name for common icons
  if [ "$icon_path" = "spotify" ]; then
    icon_path="/usr/share/icons/hicolor/256x256/apps/spotify.png"
  fi

  # Prevent totally empty bodies from causing blank popups
  if [ -z "$body" ] || [ "$body" = " " ]; then
    body="Medya Bilgisi Bulunamadı"
  fi

  # Truncate extremely long strings to prevent broken notifications
  local max_length=100
  if [ ${#body} -gt $max_length ]; then
    body="${body:0:$max_length}..."
  fi

  # Use fallback icon if specified icon doesn't exist on system
  if [[ ! -f "$icon_path" ]] && [[ "$icon_path" == /* ]]; then
    icon_path="audio-headphones"
  fi

  if command -v notify-send >/dev/null 2>&1; then
      notify-send -t "$NOTIFY_TIMEOUT" \
        -h string:"$SYNC_ID" \
        -i "$icon_path" \
        "$title" \
        "$body"
  else
      echo -e "$title\n$body"
  fi
}

# 3. Determine active player if none was explicitly targeted
get_active_player_type() {
  # Check if a player is explicitly targeted
  if [ -n "$TARGET_PLAYER" ]; then
    if [ "$TARGET_PLAYER" = "mpd" ]; then
      echo "mpd:mpd"
    elif [ "$TARGET_PLAYER" = "mpv" ]; then
      echo "mpv:mpv"
    elif [ "$TARGET_PLAYER" = "browser" ]; then
      local browser_mpris=$(playerctl -l 2>/dev/null | grep -E 'chromium|brave|firefox' | head -n1)
      if [ -n "$browser_mpris" ]; then
        echo "mpris:$browser_mpris"
      else
        echo "none:browser"
      fi
    else
      local exact_mpris=$(playerctl -l 2>/dev/null | grep -i "$TARGET_PLAYER" | head -n1)
      if [ -n "$exact_mpris" ]; then
        echo "mpris:$exact_mpris"
      else
        echo "none:$TARGET_PLAYER"
      fi
    fi
    return
  fi

  # AUTO-DETECT: Look for any player currently 'Playing'

  # Check MPV IPC via socket first
  if [ -S "$MPV_SOCKET" ] && command -v socat >/dev/null 2>&1; then
    local mpv_pause=$(echo '{ "command": ["get_property", "pause"] }' | socat - "$MPV_SOCKET" 2>/dev/null | grep -o '"data":false' || true)
    if [ -n "$mpv_pause" ]; then
      echo "mpv:mpv"
      return
    fi
  fi

  if command -v playerctl >/dev/null 2>&1; then
    local playing_mpris=$(playerctl -l 2>/dev/null | while read -r p; do
      if [ "$(playerctl -p "$p" status 2>/dev/null)" = "Playing" ]; then
        echo "$p"
        break
      fi
    done)

    if [ -n "$playing_mpris" ]; then
      echo "mpris:$playing_mpris"
      return
    fi
  fi

  # Check if MPD is playing
  if command -v mpc >/dev/null 2>&1; then
    local mpd_state=$(mpc status 2>/dev/null | grep -o '\[playing\]' || true)
    if [ -n "$mpd_state" ]; then
      echo "mpd:mpd"
      return
    fi
  fi

  # Fallback 1: MPV if socket exists
  if [ -S "$MPV_SOCKET" ]; then
    echo "mpv:mpv"
    return
  fi

  # Fallback 2: Any paused MPRIS player
  if command -v playerctl >/dev/null 2>&1; then
    local any_mpris=$(playerctl -l 2>/dev/null | head -n1)
    if [ -n "$any_mpris" ]; then
      echo "mpris:$any_mpris"
      return
    fi
  fi

  # Fallback 3: MPD if running
  if command -v mpc >/dev/null 2>&1 && mpc status >/dev/null 2>&1; then
    echo "mpd:mpd"
    return
  fi

  echo "none:none"
}

ACTIVE_INFO=$(get_active_player_type)
PLAYER_TYPE="${ACTIVE_INFO%%:*}"
PLAYER_NAME="${ACTIVE_INFO##*:}"

if [ "$PLAYER_TYPE" = "none" ]; then
  if [ "$PLAYER_NAME" = "none" ]; then
    notify_media "Medya Kontrolü" "Çalışan bir medya oynatıcı bulunamadı." "dialog-error"
  else
    notify_media "Medya Kontrolü" "$PLAYER_NAME başlatılmamış veya bulunamadı." "dialog-error"
  fi
  exit 1
fi

# 4. Execute Command based on Player Type
case "$PLAYER_TYPE" in
"mpv")
  if ! command -v socat >/dev/null 2>&1; then
    notify_media "MPV Kontrol" "socat komutu bulunamadı." "dialog-error"
    exit 1
  fi

  if [ ! -S "$MPV_SOCKET" ]; then
    notify_media "MPV Kontrol" "MPV IPC soketi bulunamadı ($MPV_SOCKET)" "dialog-error"
    exit 1
  fi

  case "$COMMAND" in
  toggle | play-pause) echo '{ "command": ["cycle", "pause"] }' | socat - "$MPV_SOCKET" >/dev/null 2>&1 ;;
  play) echo '{ "command": ["set_property", "pause", false] }' | socat - "$MPV_SOCKET" >/dev/null 2>&1 ;;
  pause) echo '{ "command": ["set_property", "pause", true] }' | socat - "$MPV_SOCKET" >/dev/null 2>&1 ;;
  next) echo '{ "command": ["playlist-next"] }' | socat - "$MPV_SOCKET" >/dev/null 2>&1 ;;
  prev | previous) echo '{ "command": ["playlist-prev"] }' | socat - "$MPV_SOCKET" >/dev/null 2>&1 ;;
  stop) echo '{ "command": ["stop"] }' | socat - "$MPV_SOCKET" >/dev/null 2>&1 ;;
  esac

  sleep 0.1

  # Get status from socket
  PAUSED=$(echo '{ "command": ["get_property", "pause"] }' | socat - "$MPV_SOCKET" 2>/dev/null | grep -o '"data":true' || true)
  TITLE=$(echo '{ "command": ["get_property", "media-title"] }' | socat - "$MPV_SOCKET" 2>/dev/null | grep -o '"data":"[^"]*"' | cut -d'"' -f4 || true)

  STATUS="Playing"
  ICON="$ICON_PLAY"
  if [ -n "$PAUSED" ]; then
    STATUS="Paused"
    ICON="$ICON_PAUSE"
  fi

  [ -z "$TITLE" ] && TITLE="Bilinmeyen Parça"

  notify_media "$ICON $STATUS (MPV)" "$TITLE" "mpv"
  ;;

"mpris")
  ACTION="$COMMAND"
  [ "$COMMAND" = "toggle" ] && ACTION="play-pause"
  [ "$COMMAND" = "prev" ] && ACTION="previous"

  if [ "$ACTION" != "status" ]; then
    playerctl -p "$PLAYER_NAME" "$ACTION" 2>/dev/null
    sleep 0.15
  fi

  STATUS=$(playerctl -p "$PLAYER_NAME" status 2>/dev/null || echo "Unknown")
  TITLE=$(playerctl -p "$PLAYER_NAME" metadata title 2>/dev/null)
  ARTIST=$(playerctl -p "$PLAYER_NAME" metadata artist 2>/dev/null)

  if [ -z "$TITLE" ]; then
    URL=$(playerctl -p "$PLAYER_NAME" metadata xesam:url 2>/dev/null)
    [ -n "$URL" ] && TITLE=$(echo "$URL" | awk -F/ '{print $NF}' | sed 's/%20/ /g')
  fi
  [ -z "$TITLE" ] && TITLE="Bilinmeyen Parça"

  ICON="$ICON_NOTE"
  [ "$STATUS" = "Playing" ] && ICON="$ICON_PLAY"
  [ "$STATUS" = "Paused" ] && ICON="$ICON_PAUSE"

  BODY="$TITLE"
  [ -n "$ARTIST" ] && BODY="$TITLE\n$ARTIST"

  PRETTY_NAME=$(echo "$PLAYER_NAME" | awk -F'.' '{print $1}' | tr '[:lower:]' '[:upper:]')
  notify_media "$ICON $STATUS ($PRETTY_NAME)" "$BODY" "$PLAYER_NAME"
  ;;

"mpd")
  case "$COMMAND" in
  toggle | play-pause) mpc toggle >/dev/null ;;
  play) mpc play >/dev/null ;;
  pause) mpc pause >/dev/null ;;
  next) mpc next >/dev/null ;;
  prev | previous) mpc prev >/dev/null ;;
  stop) mpc stop >/dev/null ;;
  esac

  sleep 0.1

  MPD_STATE=$(mpc status | grep -o '\[.*\]' | tr -d '[]' || echo "stopped")
  TITLE=$(mpc status -f "%title%" | head -n1)
  ARTIST=$(mpc status -f "%artist%" | head -n1)

  [ -z "$TITLE" ] && TITLE=$(mpc status -f "%file%" | head -n1 | awk -F/ '{print $NF}' | sed 's/\.mp3//')

  ICON="$ICON_NOTE"
  DISPLAY_STATUS="Durum"
  [ "$MPD_STATE" = "playing" ] && {
    ICON="$ICON_PLAY"
    DISPLAY_STATUS="Playing"
  }
  [ "$MPD_STATE" = "paused" ] && {
    ICON="$ICON_PAUSE"
    DISPLAY_STATUS="Paused"
  }

  BODY="$TITLE"
  [ -n "$ARTIST" ] && BODY="$TITLE\n$ARTIST"

  notify_media "$ICON $DISPLAY_STATUS (MPD)" "$BODY" "mpd"
  ;;
esac

exit 0

