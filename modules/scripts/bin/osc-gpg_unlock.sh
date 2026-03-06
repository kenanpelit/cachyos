#!/usr/bin/env bash
# ==============================================================================
# Script: osc-gpg_unlock.sh
# Description: GPG Agent unlock helper with environment refresh and signing test.
# Usage: osc-gpg_unlock.sh
# ==============================================================================

set -Eeuo pipefail

# Renk tanımlamaları
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color
BOLD='\033[1m'

# Log fonksiyonları
log_info() {
	echo -e "${BLUE}[INFO]${NC} $*"
}

log_success() {
	echo -e "${GREEN}[SUCCESS]${NC} $*"
}

log_error() {
	echo -e "${RED}[ERROR]${NC} $*"
}

log_header() {
	echo -e "\n${BOLD}${YELLOW}$*${NC}"
	echo -e "${YELLOW}==================================================${NC}\n"
}

# Hata yakalama
trap 'echo -e "\n${RED}[ERROR] Bir hata oluştu! Satır: $LINENO${NC}"; exit 1' ERR

# Banner
show_banner() {
	echo -e "${BOLD}${BLUE}"
	cat <<'EOF'
+--------------------------------------------------+
|   ____ ____   ____      _   _ _   _ _     _     |
|  / ___|  _ \ / ___|    | | | | \ | | |   | |    |
| | |  _| |_) | |  _ ____| | | |  \| | |   | |    |
| | |_| |  __/| |_| |____| |_| | |\  | |___| |___ |
|  \____|_|    \____|     \___/|_| \_|_____|_____| |
+--------------------------------------------------+
EOF
	echo -e "${NC}"
}

# Yardım metni
show_help() {
	cat <<'EOF'
osc-gpg_unlock - GPG agent unlock helper

Usage:
  osc-gpg_unlock
  osc-gpg_unlock --help

Description:
  Refreshes gpg-agent/session environment and runs a quick clearsign test to
  verify that GPG key unlock works.
EOF
}

# Argüman kontrolü
if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
	show_help
	exit 0
fi

if [[ $# -gt 0 ]]; then
	log_error "Geçersiz argüman: $1"
	log_error "Yardım için: osc-gpg_unlock --help"
	exit 1
fi

# Banner göster
show_banner

# Çevre değişkenlerini ayarla
log_header "Çevre Değişkenleri Ayarlanıyor"
export WAYLAND_DISPLAY="${WAYLAND_DISPLAY:-wayland-1}"
export XDG_RUNTIME_DIR="/run/user/$(id -u)"
export DBUS_SESSION_BUS_ADDRESS="unix:path=${XDG_RUNTIME_DIR}/bus"
export GPG_TTY="$(tty)"
log_success "Çevre değişkenleri ayarlandı"

# GPG agent'ı yeniden başlat
log_header "GPG Agent Yeniden Başlatılıyor"
log_info "GPG agent durduruluyor..."
gpgconf --kill all
sleep 1
log_info "TTY güncelleniyor..."
gpg-connect-agent updatestartuptty /bye
log_success "GPG agent yeniden başlatıldı"

# Anahtarları listele
log_header "GPG Anahtarları"
gpg -K --with-keygrip

# Test imzalama
log_header "Test İmzalama"
log_info "İmzalama işlemi başlatılıyor..."
if TEST_RESULT="$(echo "test" | gpg --clearsign 2>&1)"; then
	log_success "GPG anahtar kilidi başarıyla açıldı!"
	log_info "İmzalama işlemi başarılı"
else
	log_error "İmzalama işlemi başarısız!"
	log_error "$TEST_RESULT"
	exit 1
fi

echo -e "\n${BOLD}${GREEN}İşlem Tamamlandı!${NC}\n"
