#!/usr/bin/env bash
# English • yerel çalışma alanı başlatıcısı
# Öncelik: Chromium (uygulama) → Chrome kenp → Brave kenp (yeni pencere)
# Varsayılan: Vite dev sunucusu (5174). `pwa` argümanıyla üretim PWA'sı (8443).
set -euo pipefail

readonly DEV_URL='http://localhost:5174'
readonly PWA_URL='https://localhost:8443'
readonly DEV_SERVICE='english-dev.service'
readonly PWA_SERVICE='english.service'

accent='' muted='' red='' reset=''
if [[ -t 1 && -z "${NO_COLOR:-}" && "${TERM:-dumb}" != dumb ]]; then
    accent=$'\033[1;36m' muted=$'\033[2m' red=$'\033[1;31m' reset=$'\033[0m'
fi

info() { printf '  %s›%s %s\n' "$accent" "$reset" "$*"; }
fail() { printf '  %s✕%s %s\n' "$red" "$reset" "$*" >&2; exit 1; }

if [[ "${1:-}" == --help || "${1:-}" == -h ]]; then
    cat <<'HELP'
English — yerel çalışma alanını açar

Kullanım: start-eng.sh [pwa] [tarayıcı parametreleri...]

  (argümansız)  Vite dev sunucusu (english-dev.service) · http://localhost:5174
  pwa           Üretim PWA'sı (english.service)         · https://localhost:8443

  1. Chromium          Uygulama penceresi
  2. start-chrome-kenp  Yeni Chrome penceresi
  3. start-brave-kenp   Yeni Brave penceresi

Site/sunucu kapalıysa ilgili systemd servisi başlatılır ve hazır olması
beklenir. Servisler modüler kurulumla gelir: modules/english (dev) ve
~/.eng/site/deploy (pwa).

Renkleri kapatmak için NO_COLOR=1 kullanabilirsin.
HELP
    exit 0
fi

target='dev'
if [[ "${1:-}" == pwa || "${1:-}" == --pwa ]]; then
    target='pwa'
    shift
fi

url="$DEV_URL" target_label='dev' service="$DEV_SERVICE" ready_path=''
if [[ "$target" == pwa ]]; then
    url="$PWA_URL" target_label='PWA' service="$PWA_SERVICE" ready_path='/api/study'
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

printf '\n  %sEnglish%s %s• %s%s\n\n' "$accent" "$reset" "$muted" "$target_label" "$reset"
command -v curl >/dev/null 2>&1 || fail 'Site bağlantısını kontrol etmek için curl gerekli.'
ready() { curl --noproxy '*' --fail --silent --output /dev/null --connect-timeout 1 --max-time 1 "$url$ready_path"; }

if ! ready; then
    command -v systemctl >/dev/null 2>&1 || fail 'Siteye ulaşılamıyor ve systemctl bulunamadı.'
    info "$service başlatılıyor…"
    systemctl --user start "$service" || fail "Servis başlatılamadı. Kontrol: systemctl --user status $service"
    available=false
    for ((attempt = 0; attempt < 20; attempt++)); do
        if ready; then available=true; break; fi
        sleep 0.25
    done
    [[ "$available" == true ]] || fail "Site hazır olmadı. Ayrıntılar: journalctl --user -u $service -n 30"
fi

info "Site hazır · $url"
info "$label açılıyor…"
printf '\n'
if [[ "$launch_mode" == app ]]; then
    exec "$browser" --app="$url" "$@"
else
    exec "$browser" --new-window "$url" "$@"
fi
