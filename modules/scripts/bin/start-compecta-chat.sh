#!/usr/bin/env bash
# Google Chat (CompecTA) • compecta Chrome profiliyle başlatıcı
set -euo pipefail

readonly URL='https://chat.google.com/'
readonly PROFILE_DIR="$HOME/.chrome/compecta"

accent='' muted='' red='' reset=''
if [[ -t 1 && -z "${NO_COLOR:-}" && "${TERM:-dumb}" != dumb ]]; then
    accent=$'\033[1;36m' muted=$'\033[2m' red=$'\033[1;31m' reset=$'\033[0m'
fi

info() { printf '  %s›%s %s\n' "$accent" "$reset" "$*"; }
fail() { printf '  %s✕%s %s\n' "$red" "$reset" "$*" >&2; exit 1; }

if [[ "${1:-}" == --help || "${1:-}" == -h ]]; then
    cat <<HELP
Google Chat (CompecTA) — compecta Chrome profiliyle açar

Kullanım: start-compecta-chat.sh [tarayıcı parametreleri...]

  $URL
  Profil: $PROFILE_DIR

Gmail (compecta) ile aynı profili/oturumu paylaşır. Renkleri kapatmak
için NO_COLOR=1 kullanabilirsin.
HELP
    exit 0
fi

chrome_bin=''
for candidate in google-chrome-stable google-chrome; do
    if command -v "$candidate" >/dev/null 2>&1; then
        chrome_bin="$candidate"
        break
    fi
done
[[ -n "$chrome_bin" ]] || fail 'Google Chrome bulunamadı (google-chrome-stable / google-chrome).'

printf '\n  %sGoogle Chat (CompecTA)%s\n\n' "$accent" "$reset"
info "$chrome_bin açılıyor…"
printf '\n'

# --class YOK: appid'in hostname'den türetilen chrome-chat.google.com__-Default
# olarak kalması gerekiyor (config.conf'taki tags:4 windowrule bunu hedefliyor).
exec "$chrome_bin" --user-data-dir="$PROFILE_DIR" --profile-directory=Default --app="$URL" "$@"
