#!/usr/bin/env bash
# ==============================================================================
# Script: mpv-manager.sh
# Description: Compositor-aware MPV helper for window management and IPC control.
# Usage: mpv-manager.sh [start|playback|play-yt|save-yt|move|stick|wallpaper]
# ==============================================================================

set -euo pipefail

SOCKET_PATH="/tmp/mpvsocket"
DOWNLOADS_DIR="${HOME}/Downloads"
NOTIFICATION_TIMEOUT=1200
NIRI_MPV_STATE_FILE="${XDG_RUNTIME_DIR:-/tmp}/mpv-manager-niri-mpv.state"

compositor() {
  if [[ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]]; then
    echo "hyprland"
    return
  fi
  if [[ -n "${NIRI_SOCKET:-}" ]]; then
    echo "niri"
    return
  fi
  case "${XDG_CURRENT_DESKTOP:-}${XDG_SESSION_DESKTOP:-}" in
    *Hyprland*|*hyprland*) echo "hyprland" ;;
    *niri*|*Niri*) echo "niri" ;;
    *) echo "unknown" ;;
  esac
}

notify() {
  local title="$1"
  local message="$2"
  if command -v notify-send >/dev/null 2>&1; then
    notify-send -t "$NOTIFICATION_TIMEOUT" "$title" "$message" 2>/dev/null || true
  fi
}

die() {
  echo "mpv-manager: $*" >&2
  notify "mpv-manager" "$*"
  exit 1
}

have_socket() {
  [[ -S "$SOCKET_PATH" ]]
}

mpv_running() {
  pgrep -x mpv >/dev/null 2>&1
}

mpv_ipc() {
  local json="$1"
  command -v socat >/dev/null 2>&1 || die "socat not found"
  echo "$json" | socat - "$SOCKET_PATH" >/dev/null
}

usage() {
  cat <<'EOF'
Usage: mpv-manager <command>

Commands:
  start       Start MPV (pseudo-gui + IPC socket)
  playback    Toggle pause/play via IPC
  play-yt     Play YouTube URL from clipboard
  save-yt     Download YouTube URL from clipboard (yt-dlp)

Window management (Hyprland; limited elsewhere):
  move | stick | wallpaper
EOF
}

require_hypr() {
  command -v hyprctl >/dev/null 2>&1 || die "hyprctl not found"
  command -v jq >/dev/null 2>&1 || die "jq not found"
}

hypr_find_mpv_window() {
  hyprctl clients -j | jq -c 'map(select(.initialClass == "mpv" or .class == "mpv")) | .[0] // empty'
}

hypr_abs() {
  local n="$1"
  if [[ "$n" -lt 0 ]]; then
    echo $(( -n ))
  else
    echo "$n"
  fi
}

hypr_clamp() {
  local n="$1"
  local min="$2"
  local max="$3"
  if [[ "$max" -lt "$min" ]]; then
    max="$min"
  fi
  if [[ "$n" -lt "$min" ]]; then
    echo "$min"
  elif [[ "$n" -gt "$max" ]]; then
    echo "$max"
  else
    echo "$n"
  fi
}

hypr_find_monitor_for_window() {
  local window_info="$1"
  local monitor_id monitor_name

  monitor_id="$(jq -r '.monitor // empty' <<<"$window_info")"
  monitor_name="$(jq -r '.monitorName // empty' <<<"$window_info")"

  if [[ -n "$monitor_id" && "$monitor_id" != "null" ]]; then
    hyprctl monitors -j | jq -c --argjson id "$monitor_id" '.[] | select(.id == $id)' | head -n1
    return 0
  fi

  if [[ -n "$monitor_name" && "$monitor_name" != "null" ]]; then
    hyprctl monitors -j | jq -c --arg name "$monitor_name" '.[] | select(.name == $name)' | head -n1
    return 0
  fi

  hyprctl monitors -j | jq -c '.[] | select(.focused == true)' | head -n1
}

hypr_move_window_legacy() {
  local x_pos="$1"
  local y_pos="$2"
  local size="$3"

  if [[ "$size" -gt 300 ]]; then
    if [[ "$x_pos" -lt 500 && "$y_pos" -lt 500 ]]; then
      hyprctl dispatch moveactive exact 80% 7% >/dev/null
    elif [[ "$x_pos" -gt 1000 && "$y_pos" -lt 500 ]]; then
      hyprctl dispatch moveactive exact 80% 77% >/dev/null
    elif [[ "$x_pos" -gt 1000 && "$y_pos" -gt 500 ]]; then
      hyprctl dispatch moveactive exact 1% 77% >/dev/null
    else
      hyprctl dispatch moveactive exact 1% 7% >/dev/null
    fi
  else
    if [[ "$x_pos" -lt 500 && "$y_pos" -lt 500 ]]; then
      hyprctl dispatch moveactive exact 84% 7% >/dev/null
    elif [[ "$x_pos" -gt 1000 && "$y_pos" -lt 500 ]]; then
      hyprctl dispatch moveactive exact 84% 80% >/dev/null
    elif [[ "$x_pos" -gt 1000 && "$y_pos" -gt 500 ]]; then
      hyprctl dispatch moveactive exact 3% 80% >/dev/null
    else
      hyprctl dispatch moveactive exact 3% 7% >/dev/null
    fi
  fi
}

hypr_focus_mpv() {
  local window_info address
  window_info="$(hypr_find_mpv_window)"
  address="$(echo "$window_info" | jq -r '.address // empty')"
  [[ -n "$address" ]] || return 1
  hyprctl dispatch focuswindow "address:$address" >/dev/null
  return 0
}

hypr_start_mpv() {
  require_hypr
  command -v mpv >/dev/null 2>&1 || die "mpv not found"

  if hypr_focus_mpv; then
    notify "mpv-manager" "MPV zaten çalışıyor"
    return 0
  fi

  rm -f "$SOCKET_PATH" 2>/dev/null || true
  mpv --player-operation-mode=pseudo-gui --input-ipc-server="$SOCKET_PATH" --idle -- >/dev/null 2>&1 &
  disown || true
  notify "mpv-manager" "MPV başlatıldı"
}

hypr_move_window() {
  require_hypr

  local window_info address x_pos y_pos win_w win_h
  window_info="$(hypr_find_mpv_window)"
  address="$(echo "$window_info" | jq -r '.address // empty')"
  [[ -n "$address" ]] || die "MPV penceresi bulunamadı"

  hyprctl dispatch focuswindow "address:$address" >/dev/null
  sleep 0.1

  x_pos="$(echo "$window_info" | jq -r '.at[0] // 0')"
  y_pos="$(echo "$window_info" | jq -r '.at[1] // 0')"
  win_w="$(echo "$window_info" | jq -r '.size[0] // 0')"
  win_h="$(echo "$window_info" | jq -r '.size[1] // 0')"

  local monitor_info=""
  monitor_info="$(hypr_find_monitor_for_window "$window_info" 2>/dev/null || true)"
  if [[ -z "$monitor_info" ]]; then
    hypr_move_window_legacy "$x_pos" "$y_pos" "$win_w"
    notify "mpv-manager" "Pencere konumu güncellendi"
    return 0
  fi

  local mon_x mon_y mon_w mon_h
  local reserved_top reserved_right reserved_bottom reserved_left
  local usable_left usable_top usable_right usable_bottom
  local margin_x margin_y max_x max_y
  local tl_x tl_y tr_x tr_y br_x br_y bl_x bl_y
  local d_tl d_tr d_br d_bl current next tx ty

  mon_x="$(jq -r '.x // 0' <<<"$monitor_info")"
  mon_y="$(jq -r '.y // 0' <<<"$monitor_info")"
  mon_w="$(jq -r '.width // 0' <<<"$monitor_info")"
  mon_h="$(jq -r '.height // 0' <<<"$monitor_info")"
  reserved_top="$(jq -r '.reserved[0] // 0' <<<"$monitor_info")"
  reserved_right="$(jq -r '.reserved[1] // 0' <<<"$monitor_info")"
  reserved_bottom="$(jq -r '.reserved[2] // 0' <<<"$monitor_info")"
  reserved_left="$(jq -r '.reserved[3] // 0' <<<"$monitor_info")"

  margin_x="${MPV_HYPR_MARGIN_X:-32}"
  margin_y="${MPV_HYPR_MARGIN_Y:-96}"

  usable_left=$((mon_x + reserved_left))
  usable_top=$((mon_y + reserved_top))
  usable_right=$((mon_x + mon_w - reserved_right))
  usable_bottom=$((mon_y + mon_h - reserved_bottom))

  max_x=$((usable_right - win_w))
  max_y=$((usable_bottom - win_h))

  tl_x=$((usable_left + margin_x))
  tl_y=$((usable_top + margin_y))
  tr_x=$((usable_right - win_w - margin_x))
  tr_y=$tl_y
  br_x=$tr_x
  br_y=$((usable_bottom - win_h - margin_y))
  bl_x=$tl_x
  bl_y=$br_y

  tl_x="$(hypr_clamp "$tl_x" "$usable_left" "$max_x")"
  tr_x="$(hypr_clamp "$tr_x" "$usable_left" "$max_x")"
  br_x="$(hypr_clamp "$br_x" "$usable_left" "$max_x")"
  bl_x="$(hypr_clamp "$bl_x" "$usable_left" "$max_x")"
  tl_y="$(hypr_clamp "$tl_y" "$usable_top" "$max_y")"
  tr_y="$(hypr_clamp "$tr_y" "$usable_top" "$max_y")"
  br_y="$(hypr_clamp "$br_y" "$usable_top" "$max_y")"
  bl_y="$(hypr_clamp "$bl_y" "$usable_top" "$max_y")"

  d_tl=$(( $(hypr_abs $((x_pos - tl_x))) + $(hypr_abs $((y_pos - tl_y))) ))
  d_tr=$(( $(hypr_abs $((x_pos - tr_x))) + $(hypr_abs $((y_pos - tr_y))) ))
  d_br=$(( $(hypr_abs $((x_pos - br_x))) + $(hypr_abs $((y_pos - br_y))) ))
  d_bl=$(( $(hypr_abs $((x_pos - bl_x))) + $(hypr_abs $((y_pos - bl_y))) ))

  current="tl"
  if [[ "$d_tr" -le "$d_tl" && "$d_tr" -le "$d_br" && "$d_tr" -le "$d_bl" ]]; then
    current="tr"
  elif [[ "$d_br" -le "$d_tl" && "$d_br" -le "$d_tr" && "$d_br" -le "$d_bl" ]]; then
    current="br"
  elif [[ "$d_bl" -le "$d_tl" && "$d_bl" -le "$d_tr" && "$d_bl" -le "$d_br" ]]; then
    current="bl"
  fi

  case "$current" in
    tr) next="br"; tx="$br_x"; ty="$br_y" ;;
    br) next="bl"; tx="$bl_x"; ty="$bl_y" ;;
    bl) next="tl"; tx="$tl_x"; ty="$tl_y" ;;
    *)  next="tr"; tx="$tr_x"; ty="$tr_y" ;;
  esac

  hyprctl dispatch moveactive exact "$tx" "$ty" >/dev/null

  notify "mpv-manager" "Pencere konumu güncellendi (${current} -> ${next})"
}

hypr_toggle_stick() {
  require_hypr
  local window_info address pinned
  window_info="$(hypr_find_mpv_window)"
  address="$(echo "$window_info" | jq -r '.address // empty')"
  [[ -n "$address" ]] || die "MPV penceresi bulunamadı"

  pinned="$(echo "$window_info" | jq -r '.pinned // 0')"

  hyprctl dispatch focuswindow "address:$address" >/dev/null
  hyprctl dispatch pin "address:$address" >/dev/null

  if [[ "$pinned" == "1" ]]; then
    notify "mpv-manager" "Pencere sabitlemesi kapatıldı"
  else
    notify "mpv-manager" "Pencere sabitlendi"
  fi
}

hypr_wallpaper() {
  command -v mpvpaper >/dev/null 2>&1 || die "mpvpaper not found"
  command -v wl-paste >/dev/null 2>&1 || die "wl-paste not found"

  local output="${MPV_WALLPAPER_OUTPUT:-eDP-1}"
  local source
  source="$(wl-paste 2>/dev/null || true)"
  [[ -n "$source" ]] || die "Panoda video/URL yok"

  mpvpaper "$output" "$source" >/dev/null 2>&1 || die "mpvpaper başarısız oldu (output=$output)"
  notify "mpv-manager" "Wallpaper ayarlandı ($output)"
}

niri_require() {
  command -v niri >/dev/null 2>&1 || die "niri not found in PATH"
  if [[ -z "${NIRI_SOCKET:-}" || ! -S "${NIRI_SOCKET:-/dev/null}" ]]; then
    local runtime candidate
    runtime="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
    for candidate in \
      "$runtime"/niri.*.sock \
      "$runtime"/niri.wayland-*.sock \
      "$runtime"/niri*.sock; do
      if [[ -S "$candidate" && "$candidate" != *niri-flow* ]]; then
        export NIRI_SOCKET="$candidate"
        break
      fi
    done
  fi

  niri msg version >/dev/null 2>&1 || die "niri IPC erişilemiyor (NIRI_SOCKET yok/erişim yok)"
}

niri_find_window_id_by_app_id() {
  niri_require
  local app_id="$1"
  local id=""

  if command -v jq >/dev/null 2>&1; then
    id="$(
      niri msg -j windows 2>/dev/null \
        | jq -r --arg app "$app_id" '.. | objects | select(.app_id? == $app) | .id? // empty' \
        | head -n1
    )"
    [[ -n "$id" ]] && { echo "$id"; return 0; }
  fi

  id="$(
    niri msg windows 2>/dev/null | awk -v app="$app_id" '
      /^Window ID[[:space:]]+/ {
        id=$3
        gsub(":", "", id)
        inwin=1
        next
      }
      inwin && /App ID:/ {
        if ($0 ~ "\"" app "\"") { print id; exit }
        inwin=0
      }
    '
  )"

  [[ -n "$id" ]] || return 1
  echo "$id"
}

niri_wait_window_id_by_app_id() {
  local app_id="$1"
  local id=""
  for _ in {1..40}; do
    if id="$(niri_find_window_id_by_app_id "$app_id" 2>/dev/null)"; then
      [[ -n "$id" ]] && {
        echo "$id"
        return 0
      }
    fi
    sleep 0.05
  done
  return 1
}

niri_window_xywh_by_id() {
  local id="$1"
  local line=""

  if command -v jq >/dev/null 2>&1; then
    line="$(
      niri msg -j windows 2>/dev/null \
        | jq -r --argjson id "$id" '
            .[]
            | select(.id == $id)
            | [
                (.layout.tile_pos_in_workspace_view[0] | if . == null then empty else round end),
                (.layout.tile_pos_in_workspace_view[1] | if . == null then empty else round end),
                (.layout.window_size[0] // empty),
                (.layout.window_size[1] // empty)
              ]
            | @tsv
          ' \
        | head -n1
    )"
    if [[ -n "$line" ]]; then
      echo "${line//$'\t'/ }"
      return 0
    fi
  fi

  line="$(
    niri msg windows 2>/dev/null | awk -v want_id="$id" '
      /^Window ID[[:space:]]+/ {
        id=$3
        gsub(":", "", id)
        inwin=(id == want_id)
        x=""; y=""; w=""; h=""
        next
      }
      inwin && /^[[:space:]]*Workspace[- ]view position:/ {
        x=$3
        gsub(",", "", x)
        y=$4
      }
      inwin && /^[[:space:]]*Window size:/ {
        w=$3
        h=$5
      }
      inwin && x != "" && y != "" && w != "" && h != "" {
        print x, y, w, h
        exit
      }
    '
  )"

  [[ -n "$line" ]] || return 1
  echo "$line"
}

niri_wait_window_xywh_by_id() {
  local id="$1"
  local out=""
  for _ in {1..30}; do
    if out="$(niri_window_xywh_by_id "$id" 2>/dev/null)"; then
      [[ -n "$out" ]] && {
        echo "$out"
        return 0
      }
    fi
    sleep 0.05
  done
  return 1
}

niri_move_floating_window_by_id() {
  local id="$1"
  local x="$2"
  local y="$3"
  niri msg action move-floating-window -x "$x" -y "$y" --id "$id"
}

niri_load_mpv_state() {
  local key="$1"
  [[ -f "$NIRI_MPV_STATE_FILE" ]] || return 1
  sed -n "s/^${key}=//p" "$NIRI_MPV_STATE_FILE" | head -n1
}

niri_save_mpv_state() {
  local corner="$1"
  local top_offset="$2"
  mkdir -p "$(dirname "$NIRI_MPV_STATE_FILE")"
  cat >"$NIRI_MPV_STATE_FILE" <<EOF
corner=$corner
top_offset=$top_offset
EOF
}

niri_focused_window_xywh() {
  # Output: "x y w h" from `niri msg focused-window`
  local info x y w h
  if command -v jq >/dev/null 2>&1; then
    info="$(niri msg -j focused-window 2>/dev/null || true)"
    if [[ -n "$info" ]]; then
      x="$(jq -r '.workspace_view_position.x? | if . == null then empty else round end' <<<"$info" 2>/dev/null | head -n1)"
      y="$(jq -r '.workspace_view_position.y? | if . == null then empty else round end' <<<"$info" 2>/dev/null | head -n1)"
      w="$(jq -r '.window_size.width? // empty' <<<"$info" 2>/dev/null | head -n1)"
      h="$(jq -r '.window_size.height? // empty' <<<"$info" 2>/dev/null | head -n1)"
      if [[ -n "$x" && -n "$y" && -n "$w" && -n "$h" ]]; then
        echo "$x $y $w $h"
        return 0
      fi
    fi
  fi

  info="$(niri msg focused-window 2>/dev/null || true)"

  # Not: Pencere ekrandan taşınca niri negatif koordinat basabiliyor; o yüzden -? kullanıyoruz.
  # Ayrıca bazı sürümlerde "Workspace view position" yazımı görülebiliyor.
  x="$(echo "$info" | sed -n 's/^[[:space:]]*Workspace[- ]view position:[[:space:]]*\\(-\\{0,1\\}[0-9]\\+\\)[, ][[:space:]]*\\(-\\{0,1\\}[0-9]\\+\\).*$/\\1/p' | tail -n1)"
  y="$(echo "$info" | sed -n 's/^[[:space:]]*Workspace[- ]view position:[[:space:]]*\\(-\\{0,1\\}[0-9]\\+\\)[, ][[:space:]]*\\(-\\{0,1\\}[0-9]\\+\\).*$/\\2/p' | tail -n1)"
  w="$(echo "$info" | sed -n 's/^[[:space:]]*Window size:[[:space:]]*\\([0-9]\\+\\)[[:space:]]*x[[:space:]]*\\([0-9]\\+\\).*$/\\1/p' | tail -n1)"
  h="$(echo "$info" | sed -n 's/^[[:space:]]*Window size:[[:space:]]*\\([0-9]\\+\\)[[:space:]]*x[[:space:]]*\\([0-9]\\+\\).*$/\\2/p' | tail -n1)"

  [[ -n "$x" && -n "$y" && -n "$w" && -n "$h" ]] || return 1
  echo "$x $y $w $h"
}

niri_wait_focused_window_xywh() {
  local out
  for _ in {1..30}; do
    if out="$(niri_focused_window_xywh 2>/dev/null)"; then
      echo "$out"
      return 0
    fi
    sleep 0.05
  done
  return 1
}

niri_maybe_resize_mpv() {
  # Large mpv windows can end up huge when coming from tiling -> floating.
  # Hyprland tarafındaki davranışa benzetmek için "büyükse" 640x360'a çekiyoruz.
  niri_require

  local id="$1"
  local x y w h
  local target_w target_h
  target_w="${MPV_NIRI_WIDTH:-640}"
  target_h="${MPV_NIRI_HEIGHT:-360}"

  read -r x y w h <<<"$(niri_wait_window_xywh_by_id "$id")" || return 1

  # Küçük pencere (PiP gibi) ise elleme.
  if [[ "$w" -le 700 && "$h" -le 500 ]]; then
    return 0
  fi

  niri msg action set-window-width --id "$id" "$target_w" >/dev/null 2>&1 || true
  niri msg action set-window-height --id "$id" "$target_h" >/dev/null 2>&1 || true

  # Resize sonrası state'in oturması için kısa bekle.
  niri_wait_window_xywh_by_id "$id" >/dev/null 2>&1 || true
}

niri_focused_output_wh() {
  # Output: "W H" for the focused output.
  # Try focused-output, then fall back to outputs list.
  local info mode w h

  if command -v jq >/dev/null 2>&1; then
    info="$(niri msg -j focused-output 2>/dev/null || true)"
    if [[ -n "$info" ]]; then
      w="$(jq -r '.modes[.current_mode].width? // .current_mode.width? // .mode.width? // empty' <<<"$info" 2>/dev/null | head -n1)"
      h="$(jq -r '.modes[.current_mode].height? // .current_mode.height? // .mode.height? // empty' <<<"$info" 2>/dev/null | head -n1)"
      if [[ -n "$w" && -n "$h" ]]; then
        echo "$w $h"
        return 0
      fi
    fi
  fi

  info="$(niri msg focused-output 2>/dev/null || true)"
  mode="$(echo "$info" | sed -n 's/.*\\([0-9]\\{3,5\\}x[0-9]\\{3,5\\}\\).*/\\1/p' | head -n1)"

  if [[ -z "$mode" ]]; then
    info="$(niri msg outputs 2>/dev/null || true)"
    mode="$(
      awk '
        BEGIN { focused = 0 }
        /Focused:[[:space:]]+yes/ { focused = 1 }
        focused && match($0, /([0-9]{3,5}x[0-9]{3,5})/, m) { print m[1]; exit }
      ' <<<"$info"
    )"
    if [[ -z "$mode" ]]; then
      mode="$(echo "$info" | sed -n 's/.*\\([0-9]\\{3,5\\}x[0-9]\\{3,5\\}\\).*/\\1/p' | head -n1)"
    fi
  fi

  w="${mode%x*}"
  h="${mode#*x}"
  [[ -n "$w" && -n "$h" && "$w" != "$mode" ]] || return 1
  echo "$w $h"
}

niri_abs() {
  local n="$1"
  if [[ "$n" -lt 0 ]]; then
    echo $(( -n ))
  else
    echo "$n"
  fi
}

niri_clamp() {
  local n="$1"
  local min="$2"
  local max="$3"
  if [[ "$max" -lt "$min" ]]; then
    max="$min"
  fi
  if [[ "$n" -lt "$min" ]]; then
    echo "$min"
  elif [[ "$n" -gt "$max" ]]; then
    echo "$max"
  else
    echo "$n"
  fi
}

niri_move_cycle_corners() {
  niri_require

  local mpv_id
  mpv_id="$(niri_find_window_id_by_app_id "mpv" 2>/dev/null)" || die "MPV penceresi bulunamadı"
  niri msg action move-window-to-floating --id "$mpv_id" >/dev/null 2>&1 || true
  niri_maybe_resize_mpv "$mpv_id" || true

  local margin_x margin_y x y w h ow oh
  # Niri rule ile aynı anchor: top-right + 32/96 gap.
  margin_x="${MPV_NIRI_MARGIN_X:-32}"
  margin_y="${MPV_NIRI_MARGIN_Y:-96}"

  read -r x y w h <<<"$(niri_wait_window_xywh_by_id "$mpv_id")" || die "Niri: mpv geometry okunamadı"
  read -r ow oh <<<"$(niri_focused_output_wh)" || die "Niri: output boyutu okunamadı"

  local top_offset
  top_offset="$(niri_load_mpv_state top_offset 2>/dev/null || true)"
  if [[ -z "$top_offset" ]]; then
    top_offset=$((y - margin_y))
    if [[ "$top_offset" -lt 0 ]]; then
      top_offset=0
    fi
  fi

  local max_x max_y
  max_x=$((ow - w))
  max_y=$((oh - top_offset - h))
  if [[ "$max_x" -lt 0 ]]; then max_x=0; fi
  if [[ "$max_y" -lt 0 ]]; then max_y=0; fi

  local left_fixed right_fixed top_fixed bottom_fixed
  left_fixed="$margin_x"
  right_fixed=$((ow - w - margin_x))
  top_fixed="$margin_y"
  bottom_fixed=$((oh - top_offset - h - margin_y))

  left_fixed="$(niri_clamp "$left_fixed" 0 "$max_x")"
  right_fixed="$(niri_clamp "$right_fixed" 0 "$max_x")"
  top_fixed="$(niri_clamp "$top_fixed" 0 "$max_y")"
  bottom_fixed="$(niri_clamp "$bottom_fixed" 0 "$max_y")"

  local tl_x tl_y tr_x tr_y br_x br_y bl_x bl_y
  tl_x="$left_fixed";  tl_y=$((top_offset + top_fixed))
  tr_x="$right_fixed"; tr_y=$((top_offset + top_fixed))
  br_x="$right_fixed"; br_y=$((top_offset + bottom_fixed))
  bl_x="$left_fixed";  bl_y=$((top_offset + bottom_fixed))

  local d_tl d_tr d_br d_bl current next target_x target_y
  d_tl=$(( $(niri_abs $((x - tl_x))) + $(niri_abs $((y - tl_y))) ))
  d_tr=$(( $(niri_abs $((x - tr_x))) + $(niri_abs $((y - tr_y))) ))
  d_br=$(( $(niri_abs $((x - br_x))) + $(niri_abs $((y - br_y))) ))
  d_bl=$(( $(niri_abs $((x - bl_x))) + $(niri_abs $((y - bl_y))) ))

  # Determine nearest
  current="tl"
  if [[ "$d_tr" -le "$d_tl" && "$d_tr" -le "$d_br" && "$d_tr" -le "$d_bl" ]]; then
    current="tr"
  elif [[ "$d_br" -le "$d_tl" && "$d_br" -le "$d_tr" && "$d_br" -le "$d_bl" ]]; then
    current="br"
  elif [[ "$d_bl" -le "$d_tl" && "$d_bl" -le "$d_tr" && "$d_bl" -le "$d_br" ]]; then
    current="bl"
  fi

  case "$current" in
    tl) next="tr"; target_x="$right_fixed"; target_y="$top_fixed" ;;
    tr) next="br"; target_x="$right_fixed"; target_y="$bottom_fixed" ;;
    br) next="bl"; target_x="$left_fixed"; target_y="$bottom_fixed" ;;
    bl) next="tl"; target_x="$left_fixed"; target_y="$top_fixed" ;;
  esac

  niri_move_floating_window_by_id "$mpv_id" "$target_x" "$target_y" >/dev/null 2>&1 \
    || die "Niri: move-floating-window başarısız"

  if read -r x y w h <<<"$(niri_window_xywh_by_id "$mpv_id" 2>/dev/null)"; then
    if [[ "$next" == "tl" || "$next" == "tr" ]]; then
      top_offset=$((y - margin_y))
      if [[ "$top_offset" -lt 0 ]]; then
        top_offset=0
      fi
    fi
  fi

  niri_save_mpv_state "$next" "$top_offset"
  notify "mpv-manager" "Niri: ${current} -> ${next}"
}

niri_move_top_right() {
  niri_require

  local mpv_id="${1:-}"
  if [[ -z "$mpv_id" ]]; then
    mpv_id="$(niri_find_window_id_by_app_id "mpv" 2>/dev/null)" || die "MPV penceresi bulunamadı"
  fi

  niri msg action move-window-to-floating --id "$mpv_id" >/dev/null 2>&1 || true
  niri_maybe_resize_mpv "$mpv_id" || true

  # Compute target position based on focused output size + current window size.
  local margin_x margin_y x y w h ow oh tx ty top_offset
  margin_x="${MPV_NIRI_MARGIN_X:-32}"
  margin_y="${MPV_NIRI_MARGIN_Y:-96}"

  read -r x y w h <<<"$(niri_wait_window_xywh_by_id "$mpv_id")" || {
    notify "mpv-manager" "Niri: mpv geometry okunamadı"
    return 1
  }
  if read -r ow oh <<<"$(niri_focused_output_wh)"; then
    tx=$((ow - w - margin_x))
    ty=$((margin_y))
  else
    die "Niri: output boyutu okunamadı"
  fi

  niri_move_floating_window_by_id "$mpv_id" "$tx" "$ty" >/dev/null 2>&1 || true

  if read -r x y w h <<<"$(niri_window_xywh_by_id "$mpv_id" 2>/dev/null)"; then
    top_offset=$((y - margin_y))
    if [[ "$top_offset" -lt 0 ]]; then
      top_offset=0
    fi
    niri_save_mpv_state "tr" "$top_offset"
  fi

  notify "mpv-manager" "Niri: mpv -> (${tx}, ${ty})"
}

niri_prepare_new_mpv_window() {
  niri_require

  local mpv_id=""
  mpv_id="$(niri_wait_window_id_by_app_id "mpv")" || return 1
  niri msg action move-window-to-floating --id "$mpv_id" >/dev/null 2>&1 || true
  niri_move_top_right "$mpv_id" >/dev/null 2>&1 || true
}

start_mpv() {
  case "$(compositor)" in
    hyprland) hypr_start_mpv ;;
    niri)
      command -v mpv >/dev/null 2>&1 || die "mpv not found"
      if mpv_running && have_socket; then
        notify "mpv-manager" "MPV zaten çalışıyor"
        return 0
      fi
      rm -f "$SOCKET_PATH" 2>/dev/null || true
      mpv --player-operation-mode=pseudo-gui \
        --input-ipc-server="$SOCKET_PATH" \
        --idle \
        --autofit=640x360 \
        --autofit-larger=640x360 \
        -- >/dev/null 2>&1 &
      disown || true
      niri_prepare_new_mpv_window || true
      notify "mpv-manager" "MPV başlatıldı (Niri 640x360)"
      ;;
    *)
      command -v mpv >/dev/null 2>&1 || die "mpv not found"
      if mpv_running && have_socket; then
        notify "mpv-manager" "MPV zaten çalışıyor"
        return 0
      fi
      rm -f "$SOCKET_PATH" 2>/dev/null || true
      mpv --player-operation-mode=pseudo-gui --input-ipc-server="$SOCKET_PATH" --idle -- >/dev/null 2>&1 &
      disown || true
      notify "mpv-manager" "MPV başlatıldı"
      ;;
  esac
}

toggle_playback() {
  mpv_running || die "MPV çalışmıyor"
  have_socket || die "MPV IPC socket yok: $SOCKET_PATH"
  mpv_ipc '{ "command": ["cycle", "pause"] }'
  notify "mpv-manager" "Play/Pause"
}

read_clipboard() {
  command -v wl-paste >/dev/null 2>&1 || die "wl-paste not found"
  wl-paste 2>/dev/null || true
}

play_youtube() {
  command -v yt-dlp >/dev/null 2>&1 || die "yt-dlp not found"
  command -v mpv >/dev/null 2>&1 || die "mpv not found"

  local url
  url="$(read_clipboard)"
  [[ "$url" =~ ^https?://(www\.)?(youtube\.com|youtu\.?be)/ ]] || die "Panodaki URL YouTube değil"

  if mpv_running && have_socket; then
    mpv_ipc "{ \"command\": [\"loadfile\", \"$url\", \"replace\"] }"
    notify "mpv-manager" "YouTube yüklendi (replace)"
    return 0
  fi

  rm -f "$SOCKET_PATH" 2>/dev/null || true
  if [[ "$(compositor)" == "niri" ]]; then
    mpv --player-operation-mode=pseudo-gui \
      --input-ipc-server="$SOCKET_PATH" \
      --idle \
      --no-audio-display \
      --autofit=640x360 \
      --autofit-larger=640x360 \
      "$url" >/dev/null 2>&1 &
  else
    mpv --player-operation-mode=pseudo-gui \
      --input-ipc-server="$SOCKET_PATH" \
      --idle \
      --no-audio-display \
      "$url" >/dev/null 2>&1 &
  fi
  disown || true
  if [[ "$(compositor)" == "niri" ]]; then
    niri_prepare_new_mpv_window || true
  fi
  notify "mpv-manager" "YouTube oynatılıyor"
}

download_youtube() {
  command -v yt-dlp >/dev/null 2>&1 || die "yt-dlp not found"

  local url
  url="$(read_clipboard)"
  [[ "$url" =~ ^https?://(www\.)?(youtube\.com|youtu\.?be)/ ]] || die "Panodaki URL YouTube değil"

  mkdir -p "$DOWNLOADS_DIR"
  (cd "$DOWNLOADS_DIR" && yt-dlp -f "bestvideo+bestaudio/best" --merge-output-format mp4 --embed-thumbnail --add-metadata "$url")
  notify "mpv-manager" "İndirme tamamlandı: $DOWNLOADS_DIR"
}

main() {
  [[ $# -ge 1 ]] || { usage; exit 1; }
  cmd="$1"
  shift

  case "$cmd" in
    move|stick|wallpaper)
      case "$(compositor)" in
        hyprland)
          case "$cmd" in
            move) hypr_move_window ;;
            stick) hypr_toggle_stick ;;
            wallpaper) hypr_wallpaper ;;
          esac
          ;;
        niri)
          case "$cmd" in
            move) niri_move_cycle_corners ;;
            stick)
              # Niri'de Hyprland'daki "pin" yok; en yakın karşılık pencereyi floating'e almak.
              niri_require
              niri msg action move-window-to-floating >/dev/null 2>&1 || true
              notify "mpv-manager" "Niri: window -> floating"
              ;;
            *)
              die "Bu komut Niri'de desteklenmiyor: $cmd"
              ;;
          esac
          ;;
        *)
          die "Bu komut bu ortamda desteklenmiyor: $cmd"
          ;;
      esac
      ;;
    start)
      start_mpv
      ;;
    playback)
      toggle_playback
      ;;
    play-yt)
      play_youtube
      ;;
    save-yt)
      download_youtube
      ;;
    -h|--help|help)
      usage
      ;;
    *)
      usage
      die "Bilinmeyen komut: $cmd"
      ;;
  esac
}

main "$@"
