#!/usr/bin/env bash
set -euo pipefail

SUDO=""
if [ "$(id -u)" -ne 0 ]; then
  if ! command -v sudo >/dev/null 2>&1; then
    echo "sudo is required to install Chaotic-AUR." >&2
    exit 1
  fi
  SUDO="sudo"
fi

log() {
  printf '%s\n' "$*"
}

step() {
  printf '\n[%s] %s\n' "$1" "$2"
}

log "Chaotic-AUR kurulumu başlıyor."
log "Adımlar otomatik olarak sırayla uygulanacak."

step "0" "Pacman senkronizasyonu"
${SUDO} pacman -Sy

step "1" "Chaotic-AUR anahtarı (keyserver: hkps://keyserver.ubuntu.com)"
${SUDO} pacman-key --recv-key 3056513887B78AEB --keyserver hkps://keyserver.ubuntu.com
${SUDO} pacman-key --lsign-key 3056513887B78AEB

step "2" "Chaotic-AUR keyring ve mirrorlist paketleri"
${SUDO} pacman -U https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-keyring.pkg.tar.zst
${SUDO} pacman -U https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-mirrorlist.pkg.tar.zst

step "2.1" "Mirrorlist: CDN sabitleme"
if [ -f /etc/pacman.d/chaotic-mirrorlist ]; then
  if ! grep -q '^Server = https://cdn-mirror.chaotic.cx/\$repo/\$arch' /etc/pacman.d/chaotic-mirrorlist; then
    ${SUDO} sed -i 's|^Server = https://geo-mirror.chaotic.cx|# Server = https://geo-mirror.chaotic.cx|' /etc/pacman.d/chaotic-mirrorlist
    ${SUDO} sed -i '1i Server = https://cdn-mirror.chaotic.cx/$repo/$arch' /etc/pacman.d/chaotic-mirrorlist
  fi
fi
ls -l /etc/pacman.d/chaotic-mirrorlist

step "3" "pacman.conf içine chaotic-aur repo ekleme"
if ! grep -q '^\[chaotic-aur\]' /etc/pacman.conf; then
  ${SUDO} tee -a /etc/pacman.conf >/dev/null <<'EOF'

[chaotic-aur]
Include = /etc/pacman.d/chaotic-mirrorlist
EOF
fi

step "4" "Repo senkronizasyonu"
${SUDO} pacman -Sy
pacman -Sl chaotic-aur | head

step "5" "Keyring ve cache kontrolü (önerilen)"
${SUDO} pacman-key --check
${SUDO} pacman -Syy

step "6" "base-devel (önerilen)"
${SUDO} pacman -S --needed base-devel

log ""
log "Chaotic-AUR kurulumu tamamlandı."
