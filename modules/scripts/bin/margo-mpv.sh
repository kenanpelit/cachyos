#!/usr/bin/env bash
# ==============================================================================
# Script: margo-mpv.sh
# Description: Margo-only MPV helper. Uses `mctl` IPC (NOT `mmsg`).
# Usage: margo-mpv [start|playback|play-yt|save-yt|move|stick|top|wallpaper]
# ==============================================================================

set -euo pipefail

SOCKET_PATH="/tmp/mpvsocket"
DOWNLOADS_DIR="${HOME}/Downloads"
NOTIFICATION_TIMEOUT=1200
MPV_APP_ID="mpv"
MARGIN_X="${MARGO_MPV_MARGIN_X:-32}"
MARGIN_Y="${MARGO_MPV_MARGIN_Y:-96}"
DEFAULT_W="${MARGO_MPV_WIDTH:-640}"
DEFAULT_H="${MARGO_MPV_HEIGHT:-360}"

# ── utils ─────────────────────────────────────────────────────────────────
notify() {
  command -v notify-send >/dev/null 2>&1 \
    && notify-send -t "$NOTIFICATION_TIMEOUT" "$1" "$2" 2>/dev/null \
    || true
}

die() {
  echo "margo-mpv: $*" >&2
  notify "margo-mpv" "$*"
  exit 1
}

require() {
  command -v mctl >/dev/null 2>&1 || die "mctl bulunamadı"
  command -v jq   >/dev/null 2>&1 || die "jq bulunamadı"
}

have_socket() { [[ -S "$SOCKET_PATH" ]]; }
mpv_running()  { pgrep -x mpv >/dev/null 2>&1; }

mpv_ipc() {
  command -v socat >/dev/null 2>&1 || die "socat bulunamadı"
  echo "$1" | socat - "$SOCKET_PATH" >/dev/null
}

mpv_ipc_loadfile() {
  local target="$1" mode="${2:-replace}" json
  json="$(jq -cn --arg t "$target" --arg m "$mode" '{command:["loadfile",$t,$m]}')"
  mpv_ipc "$json"
}

read_clipboard() {
  command -v wl-paste >/dev/null 2>&1 || die "wl-paste bulunamadı"
  wl-paste 2>/dev/null || true
}

is_youtube_url() {
  [[ "${1:-}" =~ ^https?://([a-zA-Z0-9-]+\.)?(youtube\.com|youtube-nocookie\.com|youtu\.be)/ ]]
}

resolve_youtube_url() {
  local url="${1:-}"
  [[ -z "$url" ]] && url="$(read_clipboard)"
  url="$(printf '%s' "$url" | tr -d '\r' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
  is_youtube_url "$url" || die "Panodaki/argümandaki URL YouTube değil"
  printf '%s\n' "$url"
}

resolve_ytdlp_mpv_bin() {
  if command -v yt-dlp-mpv >/dev/null 2>&1; then
    command -v yt-dlp-mpv
    return 0
  fi
  local c
  for c in \
    "$HOME/.cachy/modules/mpv/scripts/yt-dlp-mpv" \
    "$HOME/.config/arch-config/modules/mpv/scripts/yt-dlp-mpv"
  do
    [[ -x "$c" ]] && { printf '%s\n' "$c"; return 0; }
  done
  return 1
}

clamp() {
  local n="$1" min="$2" max="$3"
  (( max < min )) && max="$min"
  if   (( n < min )); then echo "$min"
  elif (( n > max )); then echo "$max"
  else                     echo "$n"
  fi
}

abs() { local n="$1"; (( n < 0 )) && echo $(( -n )) || echo "$n"; }

# ── mctl helpers ──────────────────────────────────────────────────────────
mpv_client_json() {
  mctl clients --json --app-id "$MPV_APP_ID" 2>/dev/null | jq -c '.[0] // empty'
}

active_output_json() {
  mctl outputs --json 2>/dev/null | jq -c '.[] | select(.active)' | head -n1
}

output_json_by_name() {
  local name="$1"
  mctl outputs --json 2>/dev/null | jq -c --arg n "$name" '.[] | select(.name == $n)' | head -n1
}

focused_json()    { mctl focused --json 2>/dev/null; }
focused_app_id()  { focused_json | jq -r '.app_id // empty'; }

# mpv is global (or at least sticky once `margo-mpv stick` was used), so
# it appears on every tag of its monitor.  We:
#   1. Hop to mpv's monitor if needed (focusmon cycles)
#   2. If mpv's tag bitmask doesn't intersect the active view, switch view
#      to the lowest-bit tag mpv lives on
#   3. Cycle focusstack until app_id == mpv (or give up)
focus_mpv() {
  local mpv_json
  mpv_json="$(mpv_client_json)"
  [[ -n "$mpv_json" ]] || die "MPV penceresi bulunamadı"

  local mpv_monitor mpv_tags active_monitor active_tag_mask
  mpv_monitor="$(jq -r '.monitor' <<<"$mpv_json")"
  mpv_tags="$(jq -r '.tags' <<<"$mpv_json")"
  active_monitor="$(active_output_json | jq -r '.name')"

  local hops=0
  while [[ "$active_monitor" != "$mpv_monitor" && $hops -lt 4 ]]; do
    mctl dispatch focusmon 1 >/dev/null 2>&1 || break
    sleep 0.04
    active_monitor="$(active_output_json | jq -r '.name')"
    hops=$((hops + 1))
  done

  active_tag_mask="$(active_output_json | jq -r '.active_tag_mask')"
  if (( (mpv_tags & active_tag_mask) == 0 )); then
    local lowest=$(( mpv_tags & -mpv_tags ))
    mctl dispatch view "$lowest" >/dev/null 2>&1 || true
    sleep 0.04
  fi

  local i
  for i in $(seq 1 20); do
    [[ "$(focused_app_id)" == "$MPV_APP_ID" ]] && return 0
    mctl dispatch focusstack 1 >/dev/null 2>&1 || true
    sleep 0.03
  done

  [[ "$(focused_app_id)" == "$MPV_APP_ID" ]] || die "MPV odaklanamadı"
}

ensure_floating() {
  local floating
  floating="$(focused_json | jq -r '.floating')"
  [[ "$floating" == "true" ]] && return 0
  mctl dispatch togglefloating >/dev/null 2>&1 || true
  sleep 0.05
}

# mctl dispatch movewin DX DY — delta-based; calculate from current pos.
move_to() {
  local tx="$1" ty="$2" cx cy fjson
  fjson="$(focused_json)"
  cx="$(jq -r '.x' <<<"$fjson")"
  cy="$(jq -r '.y' <<<"$fjson")"
  local dx=$((tx - cx)) dy=$((ty - cy))
  mctl dispatch movewin -- "$dx" "$dy" >/dev/null 2>&1 \
    || die "movewin başarısız ($dx,$dy)"
}

resize_to() {
  local tw="$1" th="$2" cw ch fjson
  fjson="$(focused_json)"
  cw="$(jq -r '.width'  <<<"$fjson")"
  ch="$(jq -r '.height' <<<"$fjson")"
  local dw=$((tw - cw)) dh=$((th - ch))
  mctl dispatch resizewin -- "$dw" "$dh" >/dev/null 2>&1 || true
}

# ── commands ──────────────────────────────────────────────────────────────
start_mpv() {
  command -v mpv >/dev/null 2>&1 || die "mpv bulunamadı"
  if mpv_running && have_socket; then
    notify "margo-mpv" "MPV zaten çalışıyor"
    return 0
  fi
  rm -f "$SOCKET_PATH" 2>/dev/null || true
  mpv --player-operation-mode=pseudo-gui \
      --input-ipc-server="$SOCKET_PATH" \
      --idle \
      --autofit="${DEFAULT_W}x${DEFAULT_H}" \
      --autofit-larger="${DEFAULT_W}x${DEFAULT_H}" \
      -- >/dev/null 2>&1 &
  disown || true
  notify "margo-mpv" "MPV başlatıldı (${DEFAULT_W}x${DEFAULT_H})"
}

toggle_playback() {
  mpv_running || die "MPV çalışmıyor"
  have_socket || die "MPV IPC socket yok: $SOCKET_PATH"
  mpv_ipc '{"command":["cycle","pause"]}'
  notify "margo-mpv" "Play/Pause"
}

play_youtube() {
  command -v yt-dlp >/dev/null 2>&1 || die "yt-dlp bulunamadı"
  command -v mpv    >/dev/null 2>&1 || die "mpv bulunamadı"
  command -v jq     >/dev/null 2>&1 || die "jq bulunamadı"

  local url
  url="$(resolve_youtube_url "${1:-}")"

  if mpv_running && have_socket; then
    mpv_ipc_loadfile "ytdl://$url" "replace"
    notify "margo-mpv" "YouTube yüklendi (replace)"
    return 0
  fi

  rm -f "$SOCKET_PATH" 2>/dev/null || true

  local -a mpv_args=(
    --player-operation-mode=pseudo-gui
    --input-ipc-server="$SOCKET_PATH"
    --idle
    --no-audio-display
    --autofit="${DEFAULT_W}x${DEFAULT_H}"
    --autofit-larger="${DEFAULT_W}x${DEFAULT_H}"
  )
  local ytdlp_mpv
  if ytdlp_mpv="$(resolve_ytdlp_mpv_bin 2>/dev/null)"; then
    mpv_args+=(--script-opts-append="ytdl_hook-ytdl_path=$ytdlp_mpv")
  fi

  if command -v mullvad-exclude >/dev/null 2>&1; then
    mullvad-exclude mpv "${mpv_args[@]}" "ytdl://$url" >/dev/null 2>&1 &
  else
    mpv "${mpv_args[@]}" "ytdl://$url" >/dev/null 2>&1 &
  fi
  disown || true
  notify "margo-mpv" "YouTube oynatılıyor"
}

download_youtube() {
  command -v yt-dlp >/dev/null 2>&1 || die "yt-dlp bulunamadı"

  local url
  url="$(resolve_youtube_url "${1:-}")"

  mkdir -p "$DOWNLOADS_DIR"
  ( cd "$DOWNLOADS_DIR" \
      && yt-dlp -f "bestvideo+bestaudio/best" \
                --merge-output-format mp4 \
                --embed-thumbnail --add-metadata "$url" )
  notify "margo-mpv" "İndirme tamamlandı: $DOWNLOADS_DIR"
}

cmd_move() {
  require
  focus_mpv
  ensure_floating

  local fjson x y w h mon
  fjson="$(focused_json)"
  x="$(jq -r '.x'       <<<"$fjson")"
  y="$(jq -r '.y'       <<<"$fjson")"
  w="$(jq -r '.width'   <<<"$fjson")"
  h="$(jq -r '.height'  <<<"$fjson")"
  mon="$(jq -r '.monitor' <<<"$fjson")"

  # Tiling'den gelen büyük mpv'yi default boyuta indir.
  if (( w > 700 || h > 500 )); then
    resize_to "$DEFAULT_W" "$DEFAULT_H"
    sleep 0.05
    fjson="$(focused_json)"
    w="$(jq -r '.width'  <<<"$fjson")"
    h="$(jq -r '.height' <<<"$fjson")"
  fi

  local ojson mx my mw mh
  ojson="$(output_json_by_name "$mon")"
  [[ -n "$ojson" ]] || die "Output $mon bulunamadı"
  mx="$(jq -r '.x'      <<<"$ojson")"
  my="$(jq -r '.y'      <<<"$ojson")"
  mw="$(jq -r '.width'  <<<"$ojson")"
  mh="$(jq -r '.height' <<<"$ojson")"

  local max_x=$((mx + mw - w))
  local max_y=$((my + mh - h))

  local tl_x tl_y tr_x tr_y br_x br_y bl_x bl_y
  tl_x="$(clamp $((mx + MARGIN_X))             "$mx" "$max_x")"
  tl_y="$(clamp $((my + MARGIN_Y))             "$my" "$max_y")"
  tr_x="$(clamp $((mx + mw - w - MARGIN_X))    "$mx" "$max_x")"
  tr_y="$tl_y"
  br_x="$tr_x"
  br_y="$(clamp $((my + mh - h - MARGIN_Y))    "$my" "$max_y")"
  bl_x="$tl_x"
  bl_y="$br_y"

  local d_tl d_tr d_br d_bl
  d_tl=$(( $(abs $((x - tl_x))) + $(abs $((y - tl_y))) ))
  d_tr=$(( $(abs $((x - tr_x))) + $(abs $((y - tr_y))) ))
  d_br=$(( $(abs $((x - br_x))) + $(abs $((y - br_y))) ))
  d_bl=$(( $(abs $((x - bl_x))) + $(abs $((y - bl_y))) ))

  local current="tl" next tx ty
  if   (( d_tr <= d_tl && d_tr <= d_br && d_tr <= d_bl )); then current="tr"
  elif (( d_br <= d_tl && d_br <= d_tr && d_br <= d_bl )); then current="br"
  elif (( d_bl <= d_tl && d_bl <= d_tr && d_bl <= d_br )); then current="bl"
  fi

  case "$current" in
    tl) next="tr"; tx="$tr_x"; ty="$tr_y" ;;
    tr) next="br"; tx="$br_x"; ty="$br_y" ;;
    br) next="bl"; tx="$bl_x"; ty="$bl_y" ;;
    *)  next="tl"; tx="$tl_x"; ty="$tl_y" ;;
  esac

  move_to "$tx" "$ty"
  notify "margo-mpv" "Margo: ${current} → ${next}"
}

cmd_stick() {
  require
  focus_mpv
  ensure_floating
  mctl dispatch togglesticky >/dev/null 2>&1 \
    || die "togglesticky başarısız"

  local sticky
  sticky="$(focused_json | jq -r 'if .tags == 4294967295 then "on" else "off" end')"
  if [[ "$sticky" == "on" ]]; then
    notify "margo-mpv" "mpv tüm tag'lerde sabitlendi"
  else
    notify "margo-mpv" "mpv sabitlemesi kapatıldı"
  fi
}

cmd_top() {
  require
  focus_mpv
  notify "margo-mpv" "mpv öne alındı"
}

cmd_wallpaper() {
  command -v mpvpaper >/dev/null 2>&1 || die "mpvpaper bulunamadı"
  command -v wl-paste >/dev/null 2>&1 || die "wl-paste bulunamadı"
  command -v jq       >/dev/null 2>&1 || die "jq bulunamadı"

  local output="${MARGO_MPV_WALLPAPER_OUTPUT:-}"
  if [[ -z "$output" ]]; then
    if command -v mctl >/dev/null 2>&1; then
      output="$(active_output_json | jq -r '.name')"
    fi
  fi
  [[ -n "$output" && "$output" != "null" ]] || die "Aktif output bulunamadı"

  local src
  src="$(wl-paste 2>/dev/null || true)"
  [[ -n "$src" ]] || die "Panoda video/URL yok"

  mpvpaper "$output" "$src" >/dev/null 2>&1 \
    || die "mpvpaper başarısız (output=$output)"
  notify "margo-mpv" "Wallpaper ayarlandı ($output)"
}

usage() {
  cat <<'EOF'
margo-mpv — Margo compositor için MPV yardımcısı (mctl IPC)

Usage: margo-mpv <command>

Commands:
  start       MPV'yi pseudo-gui + IPC socket ile başlat
  playback    IPC ile pause/play toggle
  play-yt     Panodaki/argümandaki YouTube URL'sini oynat
              (mpv açıksa replace, kapalıysa yeni pencere)
  save-yt     YouTube videosunu ~/Downloads'a indir (yt-dlp)
  move        mpv penceresini 4 köşe arasında döndür
              (tiling'den gelirse 640x360'a indir, floating yap)
  stick       mpv'yi tüm tag'lerde sticky yap (toggle)
  top         mpv'yi odakla (gerekirse monitör/tag hop yap)
  wallpaper   Panodaki video'yu mpvpaper ile aktif output'a yansıt

Env tunables:
  MARGO_MPV_WIDTH / MARGO_MPV_HEIGHT     (default 640 x 360)
  MARGO_MPV_MARGIN_X / MARGO_MPV_MARGIN_Y (default 32 / 96)
  MARGO_MPV_WALLPAPER_OUTPUT             (default = aktif output)
EOF
}

main() {
  [[ $# -ge 1 ]] || { usage; exit 1; }
  local cmd="$1"; shift
  case "$cmd" in
    start)          start_mpv ;;
    playback)       toggle_playback ;;
    play-yt)        play_youtube     "${1:-}" ;;
    save-yt)        download_youtube "${1:-}" ;;
    move)           cmd_move ;;
    stick)          cmd_stick ;;
    top)            cmd_top ;;
    wallpaper)      cmd_wallpaper ;;
    -h|--help|help) usage ;;
    *)              usage; die "Bilinmeyen komut: $cmd" ;;
  esac
}

main "$@"
