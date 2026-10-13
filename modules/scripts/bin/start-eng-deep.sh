#!/usr/bin/env bash
# Deep English • yerel çalışma alanı başlatıcısı
# Öncelik: Chromium (uygulama) → Chrome kenp → Brave kenp (yeni pencere)
set -euo pipefail

readonly URL='http://hay.local:8096/'

accent='' muted='' red='' reset=''
if [[ -t 1 && -z "${NO_COLOR:-}" && "${TERM:-dumb}" != dumb ]]; then
    accent=$'\033[1;36m' muted=$'\033[2m' red=$'\033[1;31m' reset=$'\033[0m'
fi

info() { printf '  %s›%s %s\n' "$accent" "$reset" "$*"; }
fail() { printf '  %s✕%s %s\n' "$red" "$reset" "$*" >&2; exit 1; }

if [[ "${1:-}" == --help || "${1:-}" == -h ]]; then
    cat <<HELP
Deep English — yerel çalışma alanını açar

Kullanım: start-eng-deep.sh [tarayıcı parametreleri...]

  $URL

  1. Chromium          Uygulama penceresi
  2. start-chrome-kenp  Yeni Chrome penceresi
  3. start-brave-kenp   Yeni Brave penceresi

Renkleri kapatmak için NO_COLOR=1 kullanabilirsin.
HELP
    exit 0
fi

# Menüden başlatıldığında ~/.local/bin PATH içinde olmayabilir.
find_launcher() {
    command -v "$1" 2>/dev/null || {
        [[ -x "$HOME/.local/bin/$1" ]] && printf '%s\n' "$HOME/.local/bin/$1"
    }
}

browser='' label='' launch_mode=''
if browser=$(find_launcher chromium); then
    label='Chromium' launch_mode='app'
elif browser=$(find_launcher start-chrome-kenp); then
    label='Chrome · kenp' launch_mode='window'
elif browser=$(find_launcher start-brave-kenp); then
    label='Brave · kenp' launch_mode='window'
else
    fail 'Tarayıcı bulunamadı: chromium, start-chrome-kenp veya start-brave-kenp gerekli.'
fi

command -v curl >/dev/null 2>&1 || fail 'Site bağlantısını kontrol etmek için curl gerekli.'

# Tag 6'ya geç (appid chrome-hay.local__-Default diğer hay.local sekmeleriyle
# paylaşılıyor, title'a göre windowrule kırılgan olurdu — pencere hangi tag
# açıksa oraya düşer).
if command -v mctl >/dev/null 2>&1 && mctl status &>/dev/null; then
    mctl tags $((1 << (6 - 1))) || true
    sleep 0.3
fi

printf '\n  %sDeep English%s\n\n' "$accent" "$reset"

if ! curl --noproxy '*' --fail --silent --output /dev/null --connect-timeout 1 --max-time 1 "$URL"; then
    info "$muted site henüz cevap vermiyor, yine de açılıyor…$reset"
fi

info "$label açılıyor…"
printf '\n'
if [[ "$launch_mode" == app ]]; then
    exec "$browser" --app="$URL" "$@"
else
    exec "$browser" --new-window "$URL" "$@"
fi
