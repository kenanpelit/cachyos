#!/usr/bin/env bash
# English • yerel çalışma alanı başlatıcısı
# Öncelik: Chromium (uygulama) → Chrome kenp → Brave kenp (yeni pencere)
set -euo pipefail

readonly URL='http://127.0.0.1:8080'
readonly SERVICE='english.service'
accent='' muted='' red='' reset=''
if [[ -t 1 && -z "${NO_COLOR:-}" && "${TERM:-dumb}" != dumb ]]; then
    accent=$'\033[1;36m' muted=$'\033[2m' red=$'\033[1;31m' reset=$'\033[0m'
fi

info() { printf '  %s›%s %s\n' "$accent" "$reset" "$*"; }
fail() { printf '  %s✕%s %s\n' "$red" "$reset" "$*" >&2; exit 1; }

if [[ "${1:-}" == --help || "${1:-}" == -h ]]; then
    cat <<'HELP'
English — yerel çalışma alanını açar

Kullanım: start-eng.sh [tarayıcı parametreleri...]

  1. Chromium          Uygulama penceresi
  2. start-chrome-kenp  Yeni Chrome penceresi
  3. start-brave-kenp   Yeni Brave penceresi

Site kapalıysa english.service başlatılır ve hazır olması beklenir.
Adres: http://127.0.0.1:8080
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

browser='' label='' mode=''
if browser=$(find_launcher chromium); then
    label='Chromium' mode='app'
elif browser=$(find_launcher start-chrome-kenp); then
    label='Chrome · kenp' mode='window'
elif browser=$(find_launcher start-brave-kenp); then
    label='Brave · kenp' mode='window'
else
    fail 'Tarayıcı bulunamadı: chromium, start-chrome-kenp veya start-brave-kenp gerekli.'
fi

printf '\n  %sEnglish%s %s• çalışma alanı%s\n\n' "$accent" "$reset" "$muted" "$reset"
command -v curl >/dev/null 2>&1 || fail 'Site bağlantısını kontrol etmek için curl gerekli.'
ready() { curl --noproxy '*' --fail --silent --output /dev/null --connect-timeout 1 --max-time 1 "$URL/api/study"; }

if ! ready; then
    command -v systemctl >/dev/null 2>&1 || fail 'Siteye ulaşılamıyor ve systemctl bulunamadı.'
    info 'English servisi başlatılıyor…'
    systemctl --user start "$SERVICE" || fail 'Servis başlatılamadı. Kontrol: systemctl --user status english.service'
    available=false
    for ((attempt = 0; attempt < 20; attempt++)); do
        if ready; then available=true; break; fi
        sleep 0.25
    done
    [[ "$available" == true ]] || fail 'Site hazır olmadı. Ayrıntılar: journalctl --user -u english.service -n 30'
fi

info "Site hazır · $URL"
info "$label açılıyor…"
printf '\n'
if [[ "$mode" == app ]]; then
    exec "$browser" --app="$URL" "$@"
else
    exec "$browser" --new-window "$URL" "$@"
fi
