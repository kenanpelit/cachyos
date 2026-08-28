#!/usr/bin/env bash
# ==============================================================================
# Script: osc-browser.sh
# Description: Switch the system-wide default browser on demand (chrome/brave/
#              helium). Flips $BROWSER *and* every XDG resolver together so a
#              clicked link, a CLI tool, and the desktop all agree.
# Usage: osc-browser [chrome|brave|helium|toggle|status|list]
# ==============================================================================
set -euo pipefail

# ------------------------------------------------------------------------------
# Registry: short name -> *-kenp.desktop / start-*-kenp launcher. The desktop
# files and launchers are owned by the chrome/brave/helium modules; this script
# only picks which one is "the default". Array order is also the toggle cycle.
# ------------------------------------------------------------------------------
BROWSERS=(chrome brave helium)

desktop_for() { printf '%s-kenp.desktop' "$1"; }
launcher_for() { printf 'start-%s-kenp' "$1"; }
label_for() {
  case "$1" in
  chrome) echo "Chrome (Kenp)" ;;
  brave) echo "Brave (Kenp)" ;;
  helium) echo "Helium (Kenp)" ;;
  *) echo "$1" ;;
  esac
}

# ------------------------------------------------------------------------------
# Paths
# ------------------------------------------------------------------------------
APP_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/applications"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/osc-browser"
STATE_FILE="$STATE_DIR/current"          # new zsh shells read this (see .zshenv)
ENV_D_FILE="$HOME/.config/environment.d/10-margo-wayland.conf" # session-global $BROWSER

# MIME types / URL schemes a default browser owns. xdg-open (most link clicks),
# gio (GTK/Electron apps) and xdg-settings each key off these; set all of them.
MIME_TARGETS=(
  x-scheme-handler/http
  x-scheme-handler/https
  text/html
  application/xhtml+xml
  x-scheme-handler/about
  x-scheme-handler/unknown
)

# ------------------------------------------------------------------------------
# Output helpers
# ------------------------------------------------------------------------------
if [[ -t 1 ]]; then
  BOLD=$'\e[1m'; GREEN=$'\e[32m'; YELLOW=$'\e[33m'; RED=$'\e[31m'; NC=$'\e[0m'
else
  BOLD=""; GREEN=""; YELLOW=""; RED=""; NC=""
fi

die() { printf '%s[osc-browser]%s %s\n' "$RED" "$NC" "$*" >&2; exit 1; }
info() { printf '%s[osc-browser]%s %s\n' "$BOLD" "$NC" "$*"; }
notify() {
  command -v notify-send >/dev/null 2>&1 || return 0
  notify-send -a "osc-browser" -t 3000 "$1" "${2:-}" 2>/dev/null || true
}

is_valid() {
  local b
  for b in "${BROWSERS[@]}"; do [[ "$b" == "$1" ]] && return 0; done
  return 1
}

# Current default: prefer the explicit state file, else infer from the live XDG
# default-web-browser, else "unknown".
current_browser() {
  if [[ -r "$STATE_FILE" ]]; then
    local s; read -r s <"$STATE_FILE" 2>/dev/null || s=""
    is_valid "$s" && { echo "$s"; return 0; }
  fi
  local d; d="$(xdg-settings get default-web-browser 2>/dev/null || true)"
  case "$d" in
  chrome-kenp.desktop) echo chrome; return 0 ;;
  brave-kenp.desktop) echo brave; return 0 ;;
  helium-kenp.desktop) echo helium; return 0 ;;
  esac
  echo unknown
}

next_browser() {
  local cur="$1" i
  for i in "${!BROWSERS[@]}"; do
    if [[ "${BROWSERS[$i]}" == "$cur" ]]; then
      echo "${BROWSERS[$(((i + 1) % ${#BROWSERS[@]}))]}"
      return 0
    fi
  done
  echo "${BROWSERS[0]}" # unknown current -> first in cycle
}

# ------------------------------------------------------------------------------
# The switch
# ------------------------------------------------------------------------------
apply() {
  local b="$1"
  is_valid "$b" || die "bilinmeyen tarayıcı: $b  (geçerli: ${BROWSERS[*]})"

  local desktop launcher label
  desktop="$(desktop_for "$b")"
  launcher="$(launcher_for "$b")"
  label="$(label_for "$b")"

  [[ -f "$APP_DIR/$desktop" ]] || die "$desktop bulunamadı ($APP_DIR) — ilgili modül kurulu mu?"
  command -v "$launcher" >/dev/null 2>&1 || info "${YELLOW}uyarı:${NC} $launcher PATH'te yok (yine de devam)"

  # 1) Persist the choice (atomic write). This is the source of truth new zsh
  #    shells consult, so `echo $BROWSER` reflects it after `exec zsh`.
  mkdir -p "$STATE_DIR"
  printf '%s\n' "$b" >"$STATE_FILE.tmp.$$" && mv -f "$STATE_FILE.tmp.$$" "$STATE_FILE"

  # 2) XDG desktop layer — pin every resolver a link-click can hit.
  command -v update-desktop-database >/dev/null 2>&1 &&
    update-desktop-database "$APP_DIR" >/dev/null 2>&1 || true
  command -v xdg-settings >/dev/null 2>&1 &&
    xdg-settings set default-web-browser "$desktop" >/dev/null 2>&1 || true
  command -v xdg-mime >/dev/null 2>&1 &&
    xdg-mime default "$desktop" "${MIME_TARGETS[@]}" >/dev/null 2>&1 || true
  if command -v gio >/dev/null 2>&1; then
    local m
    for m in "${MIME_TARGETS[@]}"; do
      gio mime "$m" "$desktop" >/dev/null 2>&1 || true
    done
  fi

  # 3) $BROWSER — running session (newly spawned units/apps) + persistent boot.
  command -v systemctl >/dev/null 2>&1 &&
    systemctl --user set-environment "BROWSER=$launcher" >/dev/null 2>&1 || true
  command -v dbus-update-activation-environment >/dev/null 2>&1 &&
    dbus-update-activation-environment --systemd "BROWSER=$launcher" >/dev/null 2>&1 || true
  # environment.d is a static systemd file read at login; edit the *real* repo
  # file (follow the symlink so `sed -i` doesn't replace the link with a copy),
  # and only when the value actually changes to avoid needless churn.
  local real_env; real_env="$(realpath "$ENV_D_FILE" 2>/dev/null || echo "$ENV_D_FILE")"
  if [[ -w "$real_env" ]] && ! grep -qx "BROWSER=$launcher" "$real_env" 2>/dev/null; then
    sed -i -E "s|^BROWSER=.*|BROWSER=$launcher|" "$real_env" 2>/dev/null &&
      info "environment.d güncellendi (kalıcı boot varsayılanı)"
  fi

  info "Varsayılan tarayıcı → ${GREEN}${label}${NC}   (${desktop} · \$BROWSER=${launcher})"
  notify "Varsayılan tarayıcı" "$label"

  # A child process can't mutate the parent shell's env; tell the user how.
  if [[ "${BROWSER:-}" != "$launcher" ]]; then
    printf '%s→ bu terminalde hemen geçmek için:%s  exec zsh   (veya: export BROWSER=%s)\n' \
      "$YELLOW" "$NC" "$launcher"
  fi
}

show_status() {
  local cur; cur="$(current_browser)"
  info "Aktif varsayılan: ${GREEN}${cur}${NC}"
  local b mark note
  for b in "${BROWSERS[@]}"; do
    [[ "$b" == "$cur" ]] && mark="${GREEN}●${NC}" || mark="○"
    if [[ -f "$APP_DIR/$(desktop_for "$b")" ]]; then note=""; else note=" ${RED}(desktop yok)${NC}"; fi
    printf '  %b %-6s → %-20s %s%b\n' "$mark" "$b" "$(launcher_for "$b")" "$(desktop_for "$b")" "$note"
  done
  # No pipes here: `head`/`sed` under `set -o pipefail` trip SIGPIPE and taint
  # the status. Parameter expansion pulls the first line / value instead.
  local gioh; gioh="$(gio mime x-scheme-handler/https 2>/dev/null || true)"
  gioh="${gioh%%$'\n'*}"; gioh="${gioh##*: }"
  printf '  %s$BROWSER (bu shell)%s : %s\n' "$BOLD" "$NC" "${BROWSER:-<boş>}"
  printf '  %sxdg https default%s   : %s\n' "$BOLD" "$NC" "$(xdg-mime query default x-scheme-handler/https 2>/dev/null || echo '?')"
  printf '  %sgio  https default%s   : %s\n' "$BOLD" "$NC" "${gioh:-?}"
}

usage() {
  cat <<EOF
${BOLD}osc-browser${NC} — sistem geneli varsayılan tarayıcıyı değiştir

Kullanım:
  osc-browser <chrome|brave|helium>   belirtilen tarayıcıyı varsayılan yap
  osc-browser toggle                  sıradaki tarayıcıya geç (${BROWSERS[*]})
  osc-browser status                  mevcut durumu göster (varsayılan)
  osc-browser list                    tarayıcıları listele
  osc-browser -h | --help             bu yardım

Değiştirdiği katmanlar:
  • XDG      : xdg-settings + xdg-mime + gio  (http/https/html/about/unknown)
  • \$BROWSER : çalışan oturum (systemctl --user) + environment.d (kalıcı)
  • state    : $STATE_FILE
               (yeni zsh shell'leri okur → 'exec zsh' ile bu terminale de yansır)

Not: Ferdium/Electron uygulamalarını yeniden başlatmaya gerek yok; her link
tıklamasında XDG'yi taze okurlar.
EOF
}

main() {
  local cmd="${1:-status}"
  case "$cmd" in
  -h | --help | help) usage ;;
  status | --status) show_status ;;
  list | --list | -l) show_status ;;
  toggle | --toggle | next) apply "$(next_browser "$(current_browser)")" ;;
  chrome | brave | helium) apply "$cmd" ;;
  *) die "bilinmeyen komut: $cmd  (bkz: osc-browser --help)" ;;
  esac
}

main "$@"
