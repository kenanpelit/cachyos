#!/usr/bin/env bash
# ==============================================================================
# Script: brave-extensions.sh
# Description: Manual extension installer for Brave Browser from Chrome Web Store.
# Usage: brave-extensions.sh
# ==============================================================================

set -uo pipefail

# =============================================================================
# Renk Tanımlamaları
# =============================================================================
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly MAGENTA='\033[0;35m'
readonly CYAN='\033[0;36m'
readonly BOLD='\033[1m'
readonly NC='\033[0m'

# =============================================================================
# Konfigürasyon
# =============================================================================
readonly STORE_URL="https://chromewebstore.google.com/detail"
readonly BRAVE_DIR="$HOME/.config/BraveSoftware/Brave-Browser/Default/Extensions"
readonly SCRIPT_VERSION="2.0"

# =============================================================================
# Extension Listesi - Linux konfigürasyonu ile senkron
# =============================================================================

# Core Extensions (her zaman yüklenir)
declare -a CORE_EXTENSIONS=(
  # Translation
  "aapbdbdomjkkjkaonfhkkikfgjllcleb:Google Translate"
  "cofdbpoegempjloogbagkncekinflcnj:DeepL"
  "ibplnjkanclpjokhdolnendpplpjiace:Simple Translate"

  # Security & Privacy
  "ddkjiahejlhfcafbddmgiahcphecmpfh:uBlock Origin Lite"
  "pkehgijcmpdhfbdbbnkijodmdjhbjlgp:Privacy Badger"

  # Navigation & Productivity
  "gfbliohnnapiefjpjlpjnehglfpaknnc:Surfingkeys"
  "eekailopagacbcdloonjhbiecobagjci:Go Back With Backspace"
  "inglelmldhjcljkomheneakjkpadclhf:Keep Awake"
  "kdejdkdjdoabfihpcjmgjebcpfbhepmh:Copy Link Address"
  "kgfcmiijchdkbknmjnojfngnapkibkdh:Picture-in-Picture"
  "mbcjcnomlakhkechnbhmfjhnnllpbmlh:Tab Pinner"

  # Media
  "lmjnegcaeklhafolokijcfjliaokphfk:Video DownloadHelper"
  "ponfpcnoihfmfllpaingbgckeeldkhle:Enhancer for YouTube"

  # System Integration
  "gphhapmejobijbbhgpjhcjognlahblep:GNOME Shell Integration"

  # Other
  "njbclohenpagagafbmdipcdoogfpnfhp:Ethereum Gas Prices"
)

# Crypto Wallet Extensions (opsiyonel)
declare -a CRYPTO_EXTENSIONS=(
  "acmacodkjbdgmoleebolmdjonilkdbch:Rabby Wallet"
  "anokgmphncpekkhclmingpimjmcooifb:Compass Wallet"
  "bfnaelmomeimhlpmgjnjophhpkkoljpa:Phantom"
  "bhhhlbepdkbapadjdnnojkbgioiodbic:Solflare"
  "dlcobpjiigpikoobohmabehhmhfoodbb:Ready Wallet"
  "dmkamcknogkgcdfhhbddcghachkejeap:Keplr"
  "enabgbdfcbaehmbigakijjabdpdnimlg:Manta Wallet"
  "nebnhfamliijlghikdgcigoebonmoibm:Leo Wallet"
  "ojggmchlghnjlapmfbnjholfjkiidbch:Venom Wallet"
  "ppbibelpcjmhbdihakflkdcoccbgbkpo:UniSat Wallet"
)

# Theme Extensions (Catppuccin entegrasyonu)
declare -a THEME_EXTENSIONS=(
  "eimadpbcbfnmbkopoojfekhnkhdbieeh:Dark Reader"
  "clngdbkpkpeebahjckkjfobafhncgmne:Stylus"
  "bkkmolkhemgaeaeggcmfbghljjjoofoh:Catppuccin Mocha"
)

# =============================================================================
# Yardımcı Fonksiyonlar
# =============================================================================

print_banner() {
  echo -e "${CYAN}${BOLD}"
  cat <<"EOF"
╔═══════════════════════════════════════════════════════════════════╗
║                                                                   ║
║        Brave Browser Extensions Manuel Kurulum v2.0              ║
║        Chrome Web Store Entegrasyonu                              ║
║                                                                   ║
╚═══════════════════════════════════════════════════════════════════╝
EOF
  echo -e "${NC}"
}

print_separator() {
  echo -e "${CYAN}═══════════════════════════════════════════════════════════════════${NC}"
}

get_extension_url() {
  local ext_id="$1"
  echo "${STORE_URL}/${ext_id}"
}

is_installed() {
  local ext_id="$1"
  [[ -d "$BRAVE_DIR/$ext_id" ]]
}

get_version() {
  local ext_id="$1"
  if is_installed "$ext_id"; then
    ls -1 "$BRAVE_DIR/$ext_id" 2>/dev/null | head -n1
  else
    echo ""
  fi
}

open_extension() {
  local ext_id="$1"
  local ext_name="$2"
  local url=$(get_extension_url "$ext_id")

  echo -e "${BLUE}📦${NC} ${YELLOW}${ext_name}${NC}"
  echo -e "   ${CYAN}URL:${NC} ${url}"

  if command -v brave &>/dev/null; then
    brave "$url" >/dev/null 2>&1 &
    sleep 1.5
    return 0
  elif command -v xdg-open &>/dev/null; then
    xdg-open "$url" >/dev/null 2>&1 &
    sleep 1.5
    return 0
  else
    echo -e "   ${RED}⚠️  Tarayıcı açılamadı!${NC}"
    echo -e "   ${YELLOW}Manuel açın:${NC} ${url}"
    return 1
  fi
}

count_installed() {
  local -n arr=$1
  local count=0

  for entry in "${arr[@]}"; do
    IFS=':' read -r ext_id ext_name <<<"$entry"
    if is_installed "$ext_id"; then
      ((count++))
    fi
  done

  echo "$count"
}

# =============================================================================
# Ana Fonksiyonlar
# =============================================================================

show_menu() {
  echo ""
  print_separator
  echo -e "${YELLOW}${BOLD}Kurulum Seçenekleri:${NC}"
  print_separator
  echo -e "${CYAN} 1)${NC} ${BOLD}Tüm Core Extensions'ı Kur${NC} (15 adet)"
  echo -e "${CYAN} 2)${NC} Sadece Çeviri Araçları"
  echo -e "${CYAN} 3)${NC} Sadece Güvenlik & Gizlilik"
  echo -e "${CYAN} 4)${NC} Sadece Navigasyon & Prodüktivite"
  echo -e "${CYAN} 5)${NC} Sadece Medya Extensions'ları"
  echo -e "${CYAN} 6)${NC} ${BOLD}Kripto Cüzdanları${NC} (10 adet)"
  echo -e "${CYAN} 7)${NC} ${BOLD}Tema Extensions'ları${NC} (3 adet)"
  echo -e "${CYAN} 8)${NC} ${GREEN}Sadece Eksik Olanları Kur${NC} (Önerilen)"
  echo -e "${CYAN} 9)${NC} Yüklü Extensions Durumu"
  echo -e "${CYAN}10)${NC} Extension Listesini Göster"
  echo -e "${CYAN}11)${NC} İnteraktif Seçim Modu"
  echo -e "${CYAN} 0)${NC} ${RED}Çıkış${NC}"
  print_separator
  echo ""
}

install_category() {
  local -n extensions=$1
  local category_name="$2"
  local show_header="${3:-true}"

  if [[ "$show_header" == "true" ]]; then
    echo -e "${MAGENTA}${BOLD}🚀 $category_name Kurulacak...${NC}"
    echo ""
  fi

  local count=0
  local total=${#extensions[@]}
  local installed=0
  local skipped=0

  for entry in "${extensions[@]}"; do
    ((count++))
    IFS=':' read -r ext_id ext_name <<<"$entry"

    echo -e "${GREEN}[${count}/${total}]${NC}"

    if is_installed "$ext_id"; then
      local version=$(get_version "$ext_id")
      echo -e "   ${GREEN}✓${NC} ${ext_name} ${CYAN}(v${version})${NC} - ${YELLOW}Zaten yüklü, atlanıyor${NC}"
      ((skipped++))
    else
      open_extension "$ext_id" "$ext_name"
      ((installed++))
    fi
    echo ""
  done

  echo -e "${GREEN}✅ Tamamlandı!${NC}"
  echo -e "${CYAN}   Açılan:${NC} ${installed}"
  echo -e "${CYAN}   Atlanan:${NC} ${skipped}"
}

install_all_core() {
  install_category CORE_EXTENSIONS "Core Extensions (Tümü)"
}

install_translation() {
  local -a trans=(
    "aapbdbdomjkkjkaonfhkkikfgjllcleb:Google Translate"
    "cofdbpoegempjloogbagkncekinflcnj:DeepL"
    "ibplnjkanclpjokhdolnendpplpjiace:Simple Translate"
  )
  install_category trans "Çeviri Araçları"
}

install_security() {
  local -a sec=(
    "ddkjiahejlhfcafbddmgiahcphecmpfh:uBlock Origin Lite"
    "pkehgijcmpdhfbdbbnkijodmdjhbjlgp:Privacy Badger"
  )
  install_category sec "Güvenlik & Gizlilik"
}

install_productivity() {
  local -a prod=(
    "gfbliohnnapiefjpjlpjnehglfpaknnc:Surfingkeys"
    "eekailopagacbcdloonjhbiecobagjci:Go Back With Backspace"
    "inglelmldhjcljkomheneakjkpadclhf:Keep Awake"
    "kdejdkdjdoabfihpcjmgjebcpfbhepmh:Copy Link Address"
    "kgfcmiijchdkbknmjnojfngnapkibkdh:Picture-in-Picture"
    "mbcjcnomlakhkechnbhmfjhnnllpbmlh:Tab Pinner"
  )
  install_category prod "Navigasyon & Prodüktivite"
}

install_media() {
  local -a media=(
    "lmjnegcaeklhafolokijcfjliaokphfk:Video DownloadHelper"
    "ponfpcnoihfmfllpaingbgckeeldkhle:Enhancer for YouTube"
  )
  install_category media "Medya Extensions"
}

install_crypto() {
  install_category CRYPTO_EXTENSIONS "Kripto Cüzdanları"
}

install_themes() {
  install_category THEME_EXTENSIONS "Tema Extensions"
}

install_missing() {
  echo -e "${MAGENTA}${BOLD}🔍 Eksik Extensions Aranıyor...${NC}"
  echo ""

  if [ ! -d "$BRAVE_DIR" ]; then
    echo -e "${RED}❌ Brave extensions dizini bulunamadı!${NC}"
    echo -e "${YELLOW}   Konum:${NC} $BRAVE_DIR"
    return 1
  fi

  local -a missing=()

  # Core extensions
  for entry in "${CORE_EXTENSIONS[@]}"; do
    IFS=':' read -r ext_id ext_name <<<"$entry"
    if ! is_installed "$ext_id"; then
      missing+=("$entry")
    fi
  done

  # Theme extensions
  for entry in "${THEME_EXTENSIONS[@]}"; do
    IFS=':' read -r ext_id ext_name <<<"$entry"
    if ! is_installed "$ext_id"; then
      missing+=("$entry")
    fi
  done

  if [ ${#missing[@]} -eq 0 ]; then
    echo -e "${GREEN}${BOLD}✅ Harika! Tüm extensions zaten yüklü!${NC}"
    return 0
  fi

  echo -e "${YELLOW}📋 ${#missing[@]} extension yüklü değil:${NC}"
  echo ""

  install_category missing "Eksik Extensions" "false"
}

show_status() {
  echo -e "${MAGENTA}${BOLD}🔍 Yüklü Extensions Durumu${NC}"
  echo ""

  if [ ! -d "$BRAVE_DIR" ]; then
    echo -e "${RED}❌ Brave extensions dizini bulunamadı!${NC}"
    return 1
  fi

  # Core Extensions
  echo -e "${CYAN}${BOLD}═══ Core Extensions (15 adet) ═══${NC}"
  echo ""

  for entry in "${CORE_EXTENSIONS[@]}"; do
    IFS=':' read -r ext_id ext_name <<<"$entry"
    printf "%-40s " "$ext_name"

    if is_installed "$ext_id"; then
      local version=$(get_version "$ext_id")
      echo -e "${GREEN}✓ Yüklü${NC} ${CYAN}(v${version})${NC}"
    else
      echo -e "${RED}✗ Yüklü değil${NC}"
    fi
  done

  local core_installed=$(count_installed CORE_EXTENSIONS)
  echo ""
  echo -e "${YELLOW}İstatistik:${NC} ${GREEN}${core_installed}${NC}/${#CORE_EXTENSIONS[@]} yüklü"

  # Crypto Extensions
  echo ""
  echo -e "${CYAN}${BOLD}═══ Kripto Cüzdanları (10 adet) ═══${NC}"
  echo ""

  for entry in "${CRYPTO_EXTENSIONS[@]}"; do
    IFS=':' read -r ext_id ext_name <<<"$entry"
    printf "%-40s " "$ext_name"

    if is_installed "$ext_id"; then
      local version=$(get_version "$ext_id")
      echo -e "${GREEN}✓ Yüklü${NC} ${CYAN}(v${version})${NC}"
    else
      echo -e "${RED}✗ Yüklü değil${NC}"
    fi
  done

  local crypto_installed=$(count_installed CRYPTO_EXTENSIONS)
  echo ""
  echo -e "${YELLOW}İstatistik:${NC} ${GREEN}${crypto_installed}${NC}/${#CRYPTO_EXTENSIONS[@]} yüklü"

  # Theme Extensions
  echo ""
  echo -e "${CYAN}${BOLD}═══ Tema Extensions (3 adet) ═══${NC}"
  echo ""

  for entry in "${THEME_EXTENSIONS[@]}"; do
    IFS=':' read -r ext_id ext_name <<<"$entry"
    printf "%-40s " "$ext_name"

    if is_installed "$ext_id"; then
      local version=$(get_version "$ext_id")
      echo -e "${GREEN}✓ Yüklü${NC} ${CYAN}(v${version})${NC}"
    else
      echo -e "${RED}✗ Yüklü değil${NC}"
    fi
  done

  local theme_installed=$(count_installed THEME_EXTENSIONS)
  echo ""
  echo -e "${YELLOW}İstatistik:${NC} ${GREEN}${theme_installed}${NC}/${#THEME_EXTENSIONS[@]} yüklü"

  # Genel Özet
  echo ""
  print_separator
  local total=$((${#CORE_EXTENSIONS[@]} + ${#CRYPTO_EXTENSIONS[@]} + ${#THEME_EXTENSIONS[@]}))
  local total_installed=$((core_installed + crypto_installed + theme_installed))
  echo -e "${BOLD}TOPLAM:${NC} ${GREEN}${total_installed}${NC}/${total} extension yüklü"
  print_separator
}

show_list() {
  echo -e "${MAGENTA}${BOLD}📋 Mevcut Extension Listesi${NC}"
  echo ""

  # Core
  echo -e "${CYAN}${BOLD}═══ Core Extensions (15 adet) ═══${NC}"
  print_separator
  printf "${GREEN}%-45s ${BLUE}%-32s${NC}\n" "Extension Adı" "Extension ID"
  print_separator

  for entry in "${CORE_EXTENSIONS[@]}"; do
    IFS=':' read -r ext_id ext_name <<<"$entry"
    printf "%-45s ${BLUE}%-32s${NC}\n" "$ext_name" "$ext_id"
  done

  # Crypto
  echo ""
  echo -e "${CYAN}${BOLD}═══ Kripto Cüzdanları (10 adet) ═══${NC}"
  print_separator

  for entry in "${CRYPTO_EXTENSIONS[@]}"; do
    IFS=':' read -r ext_id ext_name <<<"$entry"
    printf "%-45s ${BLUE}%-32s${NC}\n" "$ext_name" "$ext_id"
  done

  # Theme
  echo ""
  echo -e "${CYAN}${BOLD}═══ Tema Extensions (3 adet) ═══${NC}"
  print_separator

  for entry in "${THEME_EXTENSIONS[@]}"; do
    IFS=':' read -r ext_id ext_name <<<"$entry"
    printf "%-45s ${BLUE}%-32s${NC}\n" "$ext_name" "$ext_id"
  done

  echo ""
}

interactive_install() {
  echo -e "${MAGENTA}${BOLD}📋 İnteraktif Extension Seçimi${NC}"
  echo ""

  local -a all_extensions=("${CORE_EXTENSIONS[@]}" "${CRYPTO_EXTENSIONS[@]}" "${THEME_EXTENSIONS[@]}")
  local i=1

  for entry in "${all_extensions[@]}"; do
    IFS=':' read -r ext_id ext_name <<<"$entry"
    local status=""
    if is_installed "$ext_id"; then
      status="${GREEN}[Yüklü]${NC}"
    else
      status="${RED}[Yüklü değil]${NC}"
    fi
    printf "${CYAN}%2d)${NC} %-45s %s\n" "$i" "$ext_name" "$status"
    ((i++))
  done

  echo ""
  echo -e "${GREEN}${BOLD}Seçim Yöntemleri:${NC}"
  echo -e "  • ${CYAN}Tekli:${NC} 5"
  echo -e "  • ${CYAN}Çoklu:${NC} 1,3,5,7"
  echo -e "  • ${CYAN}Aralık:${NC} 1-5"
  echo -e "  • ${CYAN}Karışık:${NC} 1-3,5,7-9"
  echo -e "  • ${CYAN}Tümü:${NC} all"
  echo ""
  read -p "Seçiminiz: " selection

  if [[ "$selection" == "all" ]]; then
    install_all_core
    install_crypto
    install_themes
    return
  fi

  # Parse selection
  local -a selected=()
  IFS=',' read -ra PARTS <<<"$selection"

  for part in "${PARTS[@]}"; do
    part=$(echo "$part" | xargs)

    if [[ "$part" =~ ^([0-9]+)-([0-9]+)$ ]]; then
      # Range
      local start=${BASH_REMATCH[1]}
      local end=${BASH_REMATCH[2]}
      for ((n = start; n <= end; n++)); do
        selected+=("$n")
      done
    elif [[ "$part" =~ ^[0-9]+$ ]]; then
      # Single number
      selected+=("$part")
    fi
  done

  # Install selected
  for num in "${selected[@]}"; do
    if [ "$num" -ge 1 ] && [ "$num" -le "${#all_extensions[@]}" ]; then
      local idx=$((num - 1))
      local entry="${all_extensions[$idx]}"
      IFS=':' read -r ext_id ext_name <<<"$entry"

      if is_installed "$ext_id"; then
        echo -e "${YELLOW}⊘${NC} $ext_name - Zaten yüklü, atlanıyor"
      else
        open_extension "$ext_id" "$ext_name"
      fi
    fi
  done

  echo ""
  echo -e "${GREEN}✅ Seçilen extensions açıldı!${NC}"
}

# =============================================================================
# Ana Program
# =============================================================================

main() {
  print_banner

  # Brave kontrolü
  if ! command -v brave &>/dev/null; then
    echo -e "${RED}${BOLD}❌ Hata:${NC} Brave tarayıcısı bulunamadı!"
    echo -e "${YELLOW}Kurulum:${NC} home-manager switch"
    exit 1
  fi

  # Extensions directory kontrolü
  if [ ! -d "$BRAVE_DIR" ]; then
    echo -e "${YELLOW}⚠️  Uyarı:${NC} Extensions dizini bulunamadı"
    echo -e "${CYAN}Konum:${NC} $BRAVE_DIR"
    echo -e "${GREEN}İpucu:${NC} Brave'i en az bir kez başlatın"
    echo ""
  fi

  # Ana döngü
  while true; do
    show_menu
    read -p "Seçiminiz (0-11): " choice

    case $choice in
    1) install_all_core ;;
    2) install_translation ;;
    3) install_security ;;
    4) install_productivity ;;
    5) install_media ;;
    6) install_crypto ;;
    7) install_themes ;;
    8) install_missing ;;
    9) show_status ;;
    10) show_list ;;
    11) interactive_install ;;
    0)
      echo ""
      echo -e "${GREEN}${BOLD}👋 İyi günler!${NC}"
      exit 0
      ;;
    *)
      echo -e "${RED}❌ Geçersiz seçim: $choice${NC}"
      ;;
    esac

    echo ""
    read -p "Devam etmek için Enter'a basın..."
  done
}

# Script başlat
main "$@"
