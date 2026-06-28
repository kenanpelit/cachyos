#!/usr/bin/env bash
# ==============================================================================
# Script: anotes.sh
# Description: Enhanced launcher for anote.sh supporting various terminal emulators.
# Usage: anotes.sh [options]
# ==============================================================================
# Authorship: Kenan Pelit
# Repository: github.com/kenanpelit
# Version: 1.4 (Hardened launcher)
# License: GPLv3

set -euo pipefail

# Compositor/DM launches may provide a minimal PATH; normalize it so helper binaries
# (anote, kitty/alacritty/foot, etc.) are always discoverable.
for path_entry in "$HOME/.local/bin" "$HOME/bin" /usr/local/bin /usr/bin /bin; do
  case ":${PATH:-}:" in
  *":$path_entry:"*) ;;
  *) PATH="$path_entry:${PATH:-}" ;;
  esac
done
export PATH

# =================================================================
# KONFİGÜRASYON
# =================================================================

ANOTE_CMD="${ANOTE_CMD:-anote}"
ANOTE_WINDOW_TITLE="${ANOTE_WINDOW_TITLE:-Anote}"
ANOTE_WINDOW_CLASS="${ANOTE_WINDOW_CLASS:-anote}"
ANOTE_INSTANCE_GROUP="${ANOTE_INSTANCE_GROUP:-anote}"
ANOTE_DIR="${ANOTE_DIR:-$HOME/.anote}"
CONFIG_FILE="${ANOTES_CONFIG_FILE:-${XDG_CONFIG_HOME:-$HOME/.config}/anotes/config}"
EDITOR="${EDITOR:-nvim}"
PREFERRED_TERMINAL="${PREFERRED_TERMINAL:-auto}"
ANOTE_USE_TMUX="${ANOTE_USE_TMUX:-false}"
ANOTE_AUTOSTART="${ANOTE_AUTOSTART:-false}"
ANOTE_KILL_PATTERN="${ANOTE_KILL_PATTERN:-}"

# Konfigürasyon dosyası varsa yükle
[[ -f "$CONFIG_FILE" ]] && source "$CONFIG_FILE"

# FZF listelerinin yukarıdan aşağı görünmesi için varsayılan yerleşim
: "${ANOTE_KILL_PATTERN:=--class[ =]${ANOTE_WINDOW_CLASS}|--app-id[ =]${ANOTE_WINDOW_CLASS}}"
: "${FZF_DEFAULT_OPTS:=--layout=reverse}"

readonly ANOTE_CMD
readonly ANOTE_WINDOW_TITLE
readonly ANOTE_WINDOW_CLASS
readonly ANOTE_INSTANCE_GROUP
readonly ANOTE_DIR
readonly CONFIG_FILE
readonly PREFERRED_TERMINAL
readonly ANOTE_USE_TMUX
readonly ANOTE_AUTOSTART
readonly ANOTE_KILL_PATTERN

export ANOTE_DIR
export EDITOR
export FZF_DEFAULT_OPTS

TERMINAL_NAME=""
TERMINAL_CMD=()

# =================================================================
# FONKSİYONLAR
# =================================================================

show_help() {
  cat <<'EOF'
┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
┃                          ANOTES - Anote Başlatıcı                            ┃
┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛

KULLANIM: anotes [SEÇENEK]

AÇIKLAMA:
    anote.sh terminal not yönetim sistemi için geliştirilmiş başlatıcı.

SEÇENEKLER:
    -t, --single       Tek satır snippet modunu başlat
    -M, --multi        Çok satırlı snippet modunu başlat
    -s, --search       Arama modunu başlat
    -A, --audit        Denetim modunu başlat (karalama defteri)
    -c, --create       Dosya oluşturma modunu başlat
    -C, --config       Anotes yapılandırma dosyasını aç
    -r, --restart      Varsa mevcut anote penceresini yeniden başlat
    -d, --daemon       Arka planda çalıştır
    -a, --auto METİN   Hızlı not ekle ve çık
    -S, --scratch      Doğrudan karalama defterini aç
    -k, --kill         Çalışan tüm anote örneklerini sonlandır
        --doctor       Başlatıcı ortamını ve terminal seçimini denetle
        --version      Sürüm bilgisini göster
    -h, --help         Bu yardım mesajını göster

ÖRNEKLER:
    anotes                           # Anote'u varsayılan ayarlarla çalıştır
    anotes -a "Yapılacak: John'u ara" # Hızlı not ekle ve çık
    anotes -r                        # Mevcut pencereyi yeniden başlat
    anotes -d -t                     # Arka planda tek satır modu

YAPILANDIRMA DOSYASI: ~/.config/anotes/config
EOF
}

show_version() {
  echo "anotes 1.4"
}

set_terminal_cmd() {
  local terminal="$1"

  case "$terminal" in
  kitty)
    TERMINAL_NAME="kitty"
    TERMINAL_CMD=(kitty --class "$ANOTE_WINDOW_CLASS" --instance-group "$ANOTE_INSTANCE_GROUP" -T "$ANOTE_WINDOW_TITLE" --single-instance)
    ;;
  alacritty)
    TERMINAL_NAME="alacritty"
    TERMINAL_CMD=(alacritty --class "$ANOTE_WINDOW_CLASS" -t "$ANOTE_WINDOW_TITLE")
    ;;
  foot)
    TERMINAL_NAME="foot"
    TERMINAL_CMD=(foot --app-id="$ANOTE_WINDOW_CLASS" --title="$ANOTE_WINDOW_TITLE")
    ;;
  *)
    return 1
    ;;
  esac
}

detect_terminal() {
  local terminals=(kitty alacritty foot)
  local term

  # Önce yapılandırmada belirtilen terminali dene
  if [[ "${PREFERRED_TERMINAL}" != "auto" ]]; then
    if command -v "$PREFERRED_TERMINAL" &>/dev/null && set_terminal_cmd "$PREFERRED_TERMINAL"; then
      return 0
    fi
    echo "⚠ Tercih edilen terminal bulunamadı veya desteklenmiyor: $PREFERRED_TERMINAL" >&2
  fi

  for term in "${terminals[@]}"; do
    if command -v "$term" &>/dev/null; then
      set_terminal_cmd "$term"
      return 0
    fi
  done

  echo "⚠ Desteklenen GUI terminal bulunamadı (kitty, alacritty, foot)" >&2
  return 1
}

shell_join() {
  local joined=""
  printf -v joined '%q ' "$@"
  printf '%s' "${joined% }"
}

check_anote() {
  command -v "$ANOTE_CMD" &>/dev/null || {
    echo "Hata: $ANOTE_CMD PATH üzerinde bulunamadı" >&2
    exit 1
  }
}

kill_anote() {
  if pkill -f -- "$ANOTE_KILL_PATTERN" 2>/dev/null; then
    echo "✓ Anote örnekleri sonlandırıldı"
  else
    echo "⚠ Çalışan anote örneği bulunamadı"
  fi
}

ensure_config() {
  [[ -f "$CONFIG_FILE" ]] && return 0

  mkdir -p "$(dirname "$CONFIG_FILE")"
  cat >"$CONFIG_FILE" <<EOF
# anotes.sh yapılandırma dosyası

# Temel ayarlar
ANOTE_CMD="$ANOTE_CMD"
ANOTE_WINDOW_TITLE="$ANOTE_WINDOW_TITLE"
ANOTE_WINDOW_CLASS="$ANOTE_WINDOW_CLASS"
ANOTE_INSTANCE_GROUP="$ANOTE_INSTANCE_GROUP"

# Terminal seçimi (auto, kitty, alacritty, foot)
PREFERRED_TERMINAL="auto"

# Ek özellikler
ANOTE_USE_TMUX=false
ANOTE_AUTOSTART=false

# Varsayılan olarak sadece anote class/app-id ile açılmış terminal örneklerini
# hedefler. Gerekirse regex olarak özelleştirilebilir.
ANOTE_KILL_PATTERN="--class[ =]anote|--app-id[ =]anote"
EOF
  echo "✓ Varsayılan yapılandırma oluşturuldu: $CONFIG_FILE"
}

run_daemon() {
  nohup "$@" >/dev/null 2>&1 &
  disown
  echo "✓ Anote arka planda başlatıldı (PID: $!)"
}

doctor_mode() {
  local terminal="none"
  if detect_terminal >/dev/null 2>&1; then
    terminal="$TERMINAL_NAME"
  fi

  cat <<EOF
anotes doctor

ANOTE_CMD:           $ANOTE_CMD
ANOTE_DIR:           $ANOTE_DIR
CONFIG_FILE:         $CONFIG_FILE
EDITOR:              $EDITOR
PREFERRED_TERMINAL:  $PREFERRED_TERMINAL
DETECTED_TERMINAL:   $terminal
ANOTE_USE_TMUX:      $ANOTE_USE_TMUX
ANOTE_KILL_PATTERN:  $ANOTE_KILL_PATTERN
FZF_DEFAULT_OPTS:    $FZF_DEFAULT_OPTS
EOF
}

# =================================================================
# ANA PROGRAM
# =================================================================

main() {
  mkdir -p "$ANOTE_DIR" 2>/dev/null

  local anote_args=()
  local daemon=false
  local restart=false

  while [[ $# -gt 0 ]]; do
    case "$1" in
    -t | --single)
      anote_args+=("-S")
      shift
      ;;
    -M | --multi)
      anote_args+=("-M")
      shift
      ;;
    -s | --search)
      anote_args+=("-s")
      shift
      ;;
    -A | --audit)
      anote_args+=("-A")
      shift
      ;;
    -S | --scratch)
      anote_args+=("--scratch")
      shift
      ;;
    -c | --create)
      anote_args+=("-e")
      shift
      ;;
    -C | --config)
      ensure_config
      "$EDITOR" "$CONFIG_FILE"
      exit 0
      ;;
    -r | --restart)
      restart=true
      shift
      ;;
    -d | --daemon)
      daemon=true
      shift
      ;;
    -a | --auto)
      shift
      [[ $# -eq 0 ]] && {
        echo "Hata: -a/--auto metin argümanı gerektirir" >&2
        exit 1
      }
      "$ANOTE_CMD" -a "$*"
      exit 0
      ;;
    -k | --kill)
      kill_anote
      exit 0
      ;;
    --doctor)
      doctor_mode
      exit 0
      ;;
    --version)
      show_version
      exit 0
      ;;
    -h | --help)
      show_help
      exit 0
      ;;
    *)
      anote_args+=("$1")
      shift
      ;;
    esac
  done

  check_anote
  [[ "$restart" == true ]] && kill_anote

  # TMUX içindeysek ve ANOTE_USE_TMUX true ise
  if [[ "${ANOTE_USE_TMUX:-false}" == true ]] &&
    [[ "${TERM_PROGRAM:-}" == "tmux" || -n "${TMUX:-}" ]]; then
    local tmux_cmd
    tmux_cmd="$(shell_join "$ANOTE_CMD" "${anote_args[@]}")"

    if [[ "$daemon" == true ]]; then
      tmux new-window -d -n "$ANOTE_WINDOW_TITLE" "$tmux_cmd"
      echo "✓ Anote tmux penceresinde başlatıldı"
    else
      tmux new-window -n "$ANOTE_WINDOW_TITLE" "$tmux_cmd"
    fi
    exit 0
  fi

  if detect_terminal; then
    local launch_cmd=("${TERMINAL_CMD[@]}" -e "$ANOTE_CMD" "${anote_args[@]}")

    if [[ "$daemon" == true ]]; then
      run_daemon "${launch_cmd[@]}"
    else
      "${launch_cmd[@]}"
    fi
  else
    # GUI terminal bulunamadı; mevcut terminalde çalıştır
    if [[ "$daemon" == true ]]; then
      run_daemon "$ANOTE_CMD" "${anote_args[@]}"
    else
      "$ANOTE_CMD" "${anote_args[@]}"
    fi
  fi
}

main "$@"
