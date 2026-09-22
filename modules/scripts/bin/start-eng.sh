#!/usr/bin/env bash
# English • yerel çalışma alanı başlatıcısı
# Öncelik: Chromium (uygulama) → Chrome kenp → Brave kenp (yeni pencere)
# Varsayılan: üretim PWA'sı (8443). `dev` argümanıyla Vite geliştirme sunucusu (5174).
set -euo pipefail

# hay.local önce denenir (Avahi ile yayınlanır, IP/Wi-Fi ağı değişse de sabit kalır - telefonun
# kullandığı adresle aynısı, bkz. src/lib/serverConfig.js DEFAULT_SERVER_URL); localhost, mDNS bir
# an için cevap vermezse (ör. avahi-daemon henüz açılmadıysa) yedek olarak dener. İkisi de aynı
# sunucuya çıkar; hangisiyle açıldığı yalnızca tarayıcının bu sayfa için ayrı tuttuğu localStorage'ı
# (tema, oynatma hızı gibi masaüstüne özel tercihler) etkiler, o yüzden hep aynısını denemek önemli.
readonly PWA_URL_CANDIDATES=('https://hay.local:8443' 'https://localhost:8443')
readonly DEV_URL='http://localhost:5174'
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

Kullanım: start-eng.sh [dev|pwa] [tarayıcı parametreleri...]

  (argümansız), pwa   Üretim PWA'sı (english.service)     · https://hay.local:8443 (yedek: localhost)
  dev                 Vite geliştirme sunucusu (english-dev.service) · http://localhost:5174

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

target='pwa'
if [[ "${1:-}" == dev || "${1:-}" == --dev ]]; then
    target='dev'
    shift
elif [[ "${1:-}" == pwa || "${1:-}" == --pwa ]]; then
    target='pwa'
    shift
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
ready_at() { curl --noproxy '*' --fail --silent --output /dev/null --connect-timeout 1 --max-time 1 "$1$2"; }

if [[ "$target" == dev ]]; then
    candidates=("$DEV_URL") target_label='dev' service="$DEV_SERVICE" ready_path=''
else
    candidates=("${PWA_URL_CANDIDATES[@]}") target_label='PWA' service="$PWA_SERVICE" ready_path='/api/study'
fi

# First candidate that answers wins (hay.local before localhost for the PWA); empty when none do.
find_ready_url() {
    for candidate in "${candidates[@]}"; do
        if ready_at "$candidate" "$ready_path"; then printf '%s\n' "$candidate"; return 0; fi
    done
    return 1
}

printf '\n  %sEnglish%s %s• %s%s\n\n' "$accent" "$reset" "$muted" "$target_label" "$reset"

url=$(find_ready_url || true)
if [[ -z "$url" ]]; then
    command -v systemctl >/dev/null 2>&1 || fail 'Siteye ulaşılamıyor ve systemctl bulunamadı.'
    info "$service başlatılıyor…"
    systemctl --user start "$service" || fail "Servis başlatılamadı. Kontrol: systemctl --user status $service"
    for ((attempt = 0; attempt < 20; attempt++)); do
        url=$(find_ready_url || true)
        [[ -n "$url" ]] && break
        sleep 0.25
    done
    [[ -n "$url" ]] || fail "Site hazır olmadı. Ayrıntılar: journalctl --user -u $service -n 30"
fi

info "Site hazır · $url"
info "$label açılıyor…"
printf '\n'
if [[ "$launch_mode" == app ]]; then
    exec "$browser" --app="$url" "$@"
else
    exec "$browser" --new-window "$url" "$@"
fi
