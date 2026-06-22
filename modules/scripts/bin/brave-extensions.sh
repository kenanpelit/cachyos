#!/usr/bin/env bash
# ==============================================================================
# Script: brave-extensions.sh
# Description: Install Chrome Web Store extensions into ANY isolated Brave
#              profile — from a curated catalog OR by copying another profile's
#              installed set. Opens each extension's Web Store page in the chosen
#              target profile so you click "Add to Brave" once.
#
#   Why open the Web Store instead of copying files? Chromium signs every
#   profile's extension list with a machine-specific HMAC ("Secure
#   Preferences"); a file-level copy is detected as tampering and the extension
#   is disabled/removed. The Web Store path is the only robust per-profile
#   install. (Merged from the old brave-extensions + brave-ext-copy.)
#
# Profiles live under ~/.brave/isolated/<profile> (override with ISOLATED_ROOT).
#
# Usage: brave-extensions [target-profile]
#        ISOLATED_ROOT=... brave-extensions
# ==============================================================================

set -uo pipefail

# =============================================================================
# Renkler (TTY-aware)
# =============================================================================
if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
  RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
  BLUE='\033[0;34m'; MAGENTA='\033[0;35m'; CYAN='\033[0;36m'
  BOLD='\033[1m'; NC='\033[0m'
else
  RED=''; GREEN=''; YELLOW=''; BLUE=''; MAGENTA=''; CYAN=''; BOLD=''; NC=''
fi

# =============================================================================
# Konfigürasyon
# =============================================================================
readonly STORE_URL="https://chromewebstore.google.com/detail"
readonly ISOLATED_ROOT="${ISOLATED_ROOT:-$HOME/.brave/isolated}"

TARGET=""           # seçilen hedef profil (select_target ile atanır)
TARGET_EXT_DIR=""   # hedef profilin Extensions dizini

# =============================================================================
# Eklenti Kataloğu  (format: "<id>:<görünen ad>")
# =============================================================================

# Core Extensions (her zaman önerilir)
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
# Yardımcılar
# =============================================================================

print_separator() {
  echo -e "${CYAN}═══════════════════════════════════════════════════════════════════${NC}"
}

print_banner() {
  echo -e "${CYAN}${BOLD}"
  cat <<"EOF"
╔═══════════════════════════════════════════════════════════════════╗
║          Brave Extensions — çoklu-profil kurulum (v3.0)           ║
║          Chrome Web Store · ~/.brave/isolated                     ║
╚═══════════════════════════════════════════════════════════════════╝
EOF
  echo -e "${NC}"
}

get_extension_url() { echo "${STORE_URL}/$1"; }

# Hedef profile göre kontroller
is_installed() { [[ -d "$TARGET_EXT_DIR/$1" ]]; }

get_version() {
  is_installed "$1" || { echo ""; return; }
  ls -1 "$TARGET_EXT_DIR/$1" 2>/dev/null | sort -V | tail -n1
}

count_installed() {
  local -n _arr="$1"
  local c=0 entry id
  for entry in "${_arr[@]}"; do
    id="${entry%%:*}"
    is_installed "$id" && ((c++))
  done
  echo "$c"
}

# İzole profilleri listele
list_profiles() {
  find "$ISOLATED_ROOT" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' 2>/dev/null | sort
}

# Verilen URL'leri HEDEF profilde tek pencerede aç
open_urls_in_target() {
  local urls=("$@")
  ((${#urls[@]})) || return 0
  if command -v "start-brave-$TARGET" >/dev/null 2>&1; then
    "start-brave-$TARGET" "${urls[@]}" >/dev/null 2>&1 &
  else
    local brave_cmd
    brave_cmd="$(command -v brave-origin-beta || command -v brave-browser || command -v brave || true)"
    [[ -n "$brave_cmd" ]] || {
      echo -e "${RED}start-brave-$TARGET ve brave bulunamadı.${NC}" >&2
      return 1
    }
    "$brave_cmd" --user-data-dir="$ISOLATED_ROOT/$TARGET" --profile-directory=Default \
      "${urls[@]}" >/dev/null 2>&1 &
  fi
  disown 2>/dev/null || true
}

# Bir eklentinin görünen adını çöz (kaynak profil bağlamında).
# Args: <id> <src_pref> <src_ext>
resolve_name() {
  local id="$1" src_pref="$2" src_ext="$3" name=""
  name="$(jq -r --arg id "$id" '.extensions.settings[$id].manifest.name // empty' "$src_pref" 2>/dev/null)"

  if [[ -z "$name" || "$name" == __MSG_* ]]; then
    local extdir="$src_ext/$id" ver mf key locale msg l
    ver="$(ls -1 "$extdir" 2>/dev/null | sort -V | tail -n1)"
    mf="$extdir/$ver/manifest.json"
    [[ -f "$mf" ]] || { printf '%s' "$id"; return; }
    [[ -z "$name" ]] && name="$(jq -r '.name // empty' "$mf" 2>/dev/null)"
    if [[ "$name" == __MSG_* ]]; then
      key="${name#__MSG_}"; key="${key%__}"
      locale="$(jq -r '.default_locale // "en"' "$mf" 2>/dev/null)"
      for l in "$locale" en en_US en_GB; do
        msg="$(jq -r --arg k "$key" '.[$k].message // empty' \
          "$extdir/$ver/_locales/$l/messages.json" 2>/dev/null)"
        [[ -n "$msg" ]] && { printf '%s' "$msg"; return; }
      done
    fi
  fi
  printf '%s' "${name:-$id}"
}

# =============================================================================
# Hedef profil seçimi
# =============================================================================
set_target() { TARGET_EXT_DIR="$ISOLATED_ROOT/$TARGET/Default/Extensions"; }

select_target() {
  local want="${1:-}"
  local -a profiles
  mapfile -t profiles < <(list_profiles)
  ((${#profiles[@]})) || {
    echo -e "${RED}İzole profil yok: $ISOLATED_ROOT${NC}" >&2
    exit 1
  }

  if [[ -n "$want" ]]; then
    local p
    for p in "${profiles[@]}"; do
      [[ "$p" == "$want" ]] && { TARGET="$want"; set_target; return; }
    done
    echo -e "${YELLOW}'$want' profili bulunamadı; listeden seç.${NC}"
  fi

  if command -v fzf >/dev/null 2>&1; then
    TARGET="$(printf '%s\n' "${profiles[@]}" \
      | fzf --no-multi --height=40% --reverse --prompt='Hedef profil > ')"
  else
    local i=1 p n
    for p in "${profiles[@]}"; do printf "%2d) %s\n" "$i" "$p"; ((i++)); done
    read -r -p "Hedef profil no: " n
    [[ "$n" =~ ^[0-9]+$ ]] && TARGET="${profiles[$((n - 1))]:-}"
  fi
  [[ -n "$TARGET" ]] || { echo "Hedef seçilmedi."; exit 0; }
  set_target
}

# =============================================================================
# Kurulum
# =============================================================================

# Bir eklenti listesini HEDEF profile kur (yüklü olanları atlar, kalanı aç).
# Args: <kategori-adı> <entry...>   (entry = "id:ad")
install_list() {
  local category="$1"; shift
  local -a _exts=("$@")
  echo -e "${MAGENTA}${BOLD}🚀 ${category} → ${TARGET}${NC}\n"

  local urls=() opened=0 skipped=0 entry id name
  for entry in "${_exts[@]}"; do
    IFS=':' read -r id name <<<"$entry"
    if is_installed "$id"; then
      echo -e "  ${GREEN}✓${NC} ${name} ${CYAN}(v$(get_version "$id"))${NC} — zaten yüklü"
      ((skipped++))
    else
      echo -e "  ${BLUE}+${NC} ${name}"
      urls+=("$(get_extension_url "$id")")
      ((opened++))
    fi
  done

  echo
  if ((${#urls[@]})); then
    echo -e "${CYAN}${#urls[@]} Web Store sayfası '${TARGET}' profilinde açılıyor — her birinde \"Add to Brave\" tıkla.${NC}"
    open_urls_in_target "${urls[@]}"
  else
    echo -e "${GREEN}Hepsi zaten yüklü.${NC}"
  fi
  echo -e "${CYAN}Açılan:${NC} ${opened}  ${CYAN}Atlanan:${NC} ${skipped}"
}

install_translation() {
  install_list "Çeviri Araçları" \
    "aapbdbdomjkkjkaonfhkkikfgjllcleb:Google Translate" \
    "cofdbpoegempjloogbagkncekinflcnj:DeepL" \
    "ibplnjkanclpjokhdolnendpplpjiace:Simple Translate"
}

install_security() {
  install_list "Güvenlik & Gizlilik" \
    "ddkjiahejlhfcafbddmgiahcphecmpfh:uBlock Origin Lite" \
    "pkehgijcmpdhfbdbbnkijodmdjhbjlgp:Privacy Badger"
}

install_productivity() {
  install_list "Navigasyon & Prodüktivite" \
    "gfbliohnnapiefjpjlpjnehglfpaknnc:Surfingkeys" \
    "eekailopagacbcdloonjhbiecobagjci:Go Back With Backspace" \
    "inglelmldhjcljkomheneakjkpadclhf:Keep Awake" \
    "kdejdkdjdoabfihpcjmgjebcpfbhepmh:Copy Link Address" \
    "kgfcmiijchdkbknmjnojfngnapkibkdh:Picture-in-Picture" \
    "mbcjcnomlakhkechnbhmfjhnnllpbmlh:Tab Pinner"
}

install_media() {
  install_list "Medya" \
    "lmjnegcaeklhafolokijcfjliaokphfk:Video DownloadHelper" \
    "ponfpcnoihfmfllpaingbgckeeldkhle:Enhancer for YouTube"
}

install_missing() {
  echo -e "${MAGENTA}${BOLD}🔍 Eksik eklentiler (core + tema) → ${TARGET}${NC}\n"
  local -a missing=() entry id name
  for entry in "${CORE_EXTENSIONS[@]}" "${THEME_EXTENSIONS[@]}"; do
    IFS=':' read -r id name <<<"$entry"
    is_installed "$id" || missing+=("$entry")
  done
  if ((${#missing[@]} == 0)); then
    echo -e "${GREEN}${BOLD}✅ Tüm core+tema eklentileri zaten yüklü.${NC}"
    return 0
  fi
  echo -e "${YELLOW}${#missing[@]} eklenti eksik.${NC}\n"
  install_list "Eksik Eklentiler" "${missing[@]}"
}

# Başka bir profilden kopyala (eski brave-ext-copy davranışı; hedef = TARGET)
copy_from_profile() {
  command -v fzf >/dev/null 2>&1 || { echo -e "${RED}fzf gerekli (kurulu değil).${NC}" >&2; return 1; }
  command -v jq  >/dev/null 2>&1 || { echo -e "${RED}jq gerekli (kurulu değil).${NC}" >&2; return 1; }

  local -a profiles
  mapfile -t profiles < <(list_profiles | grep -vx "$TARGET")
  ((${#profiles[@]})) || { echo -e "${YELLOW}Kaynak için başka profil yok.${NC}"; return 1; }

  local source
  source="$(printf '%s\n' "${profiles[@]}" \
    | fzf --no-multi --height=40% --reverse --prompt="Kaynak profil (→ $TARGET) > ")"
  [[ -n "$source" ]] || { echo "Kaynak seçilmedi."; return 0; }

  local src_dir="$ISOLATED_ROOT/$source/Default"
  local src_pref="$src_dir/Preferences"
  local src_ext="$src_dir/Extensions"
  [[ -d "$src_ext" ]] || { echo -e "${RED}Kaynak eklentileri yok: $src_ext${NC}" >&2; return 1; }

  # Kaynak profildeki gerçek eklentilerden "id<TAB>ad" listesi kur
  local items=() d id
  for d in "$src_ext"/*/; do
    id="$(basename "$d")"
    [[ "$id" == "Temp" ]] && continue
    [[ "$id" =~ ^[a-p]{32}$ ]] || continue
    items+=("$id"$'\t'"$(resolve_name "$id" "$src_pref" "$src_ext")")
  done
  ((${#items[@]})) || { echo -e "${YELLOW}'$source' içinde eklenti bulunamadı.${NC}"; return 1; }

  local selected
  selected="$(printf '%s\n' "${items[@]}" | sort -f -t$'\t' -k2 \
    | fzf --multi --reverse --height=70% --with-nth=2.. --delimiter=$'\t' \
        --prompt="$source → $TARGET  (TAB çoklu seç, Enter onayla) > " \
        --header='Seçilenlerin Web Store sayfaları hedef profilde açılır; her birinde "Add" tıkla.')"
  [[ -n "$selected" ]] || { echo "Bir şey seçilmedi."; return 0; }

  local urls=() name
  while IFS=$'\t' read -r id name; do
    [[ -n "$id" ]] || continue
    if is_installed "$id"; then
      echo -e "  ${GREEN}✓${NC} ${name} — ${TARGET} içinde zaten yüklü"
    else
      urls+=("$(get_extension_url "$id")")
      echo -e "  ${BLUE}+${NC} ${name}"
    fi
  done <<<"$selected"

  echo
  if ((${#urls[@]})); then
    echo -e "${CYAN}${#urls[@]} sayfa '${TARGET}' profilinde açılıyor.${NC}"
    open_urls_in_target "${urls[@]}"
  else
    echo -e "${GREEN}Seçilenlerin hepsi zaten yüklü.${NC}"
  fi
}

# =============================================================================
# Görüntüleme
# =============================================================================

_status_section() {
  local -n _arr="$1"
  local title="$2" entry id name
  echo -e "${CYAN}${BOLD}═══ ${title} (${#_arr[@]} adet) ═══${NC}\n"
  for entry in "${_arr[@]}"; do
    IFS=':' read -r id name <<<"$entry"
    printf "%-40s " "$name"
    if is_installed "$id"; then
      echo -e "${GREEN}✓ Yüklü${NC} ${CYAN}(v$(get_version "$id"))${NC}"
    else
      echo -e "${RED}✗ Yüklü değil${NC}"
    fi
  done
  echo -e "\n${YELLOW}İstatistik:${NC} ${GREEN}$(count_installed "$1")${NC}/${#_arr[@]} yüklü\n"
}

show_status() {
  echo -e "${MAGENTA}${BOLD}🔍 '${TARGET}' profilinde eklenti durumu${NC}\n"
  _status_section CORE_EXTENSIONS "Core Extensions"
  _status_section CRYPTO_EXTENSIONS "Kripto Cüzdanları"
  _status_section THEME_EXTENSIONS "Tema Extensions"

  local total=$((${#CORE_EXTENSIONS[@]} + ${#CRYPTO_EXTENSIONS[@]} + ${#THEME_EXTENSIONS[@]}))
  local inst=$(( $(count_installed CORE_EXTENSIONS) + $(count_installed CRYPTO_EXTENSIONS) + $(count_installed THEME_EXTENSIONS) ))
  print_separator
  echo -e "${BOLD}TOPLAM (${TARGET}):${NC} ${GREEN}${inst}${NC}/${total} katalog eklentisi yüklü"
  print_separator
}

_list_section() {
  local -n _arr="$1"
  local title="$2" entry id name
  echo -e "${CYAN}${BOLD}═══ ${title} (${#_arr[@]} adet) ═══${NC}"
  print_separator
  for entry in "${_arr[@]}"; do
    IFS=':' read -r id name <<<"$entry"
    printf "%-45s ${BLUE}%-32s${NC}\n" "$name" "$id"
  done
  echo
}

show_list() {
  echo -e "${MAGENTA}${BOLD}📋 Katalog${NC}\n"
  _list_section CORE_EXTENSIONS "Core Extensions"
  _list_section CRYPTO_EXTENSIONS "Kripto Cüzdanları"
  _list_section THEME_EXTENSIONS "Tema Extensions"
}

interactive_install() {
  echo -e "${MAGENTA}${BOLD}📋 İnteraktif seçim → ${TARGET}${NC}\n"
  local -a all=("${CORE_EXTENSIONS[@]}" "${CRYPTO_EXTENSIONS[@]}" "${THEME_EXTENSIONS[@]}")
  local i=1 entry id name status
  for entry in "${all[@]}"; do
    IFS=':' read -r id name <<<"$entry"
    if is_installed "$id"; then status="${GREEN}[Yüklü]${NC}"; else status="${RED}[Yok]${NC}"; fi
    printf "${CYAN}%2d)${NC} %-45s %b\n" "$i" "$name" "$status"
    ((i++))
  done

  echo -e "\n${GREEN}${BOLD}Seçim:${NC} tekli '5' · çoklu '1,3,5' · aralık '1-5' · karışık '1-3,5' · 'all'\n"
  local selection
  read -r -p "Seçiminiz: " selection
  [[ -n "$selection" ]] || return 0

  local -a nums=()
  if [[ "$selection" == "all" ]]; then
    for ((n = 1; n <= ${#all[@]}; n++)); do nums+=("$n"); done
  else
    local part
    IFS=',' read -ra parts <<<"$selection"
    for part in "${parts[@]}"; do
      part="$(echo "$part" | xargs)"
      if [[ "$part" =~ ^([0-9]+)-([0-9]+)$ ]]; then
        for ((n = BASH_REMATCH[1]; n <= BASH_REMATCH[2]; n++)); do nums+=("$n"); done
      elif [[ "$part" =~ ^[0-9]+$ ]]; then
        nums+=("$part")
      fi
    done
  fi

  local urls=() num idx
  for num in "${nums[@]}"; do
    ((num >= 1 && num <= ${#all[@]})) || continue
    idx=$((num - 1))
    IFS=':' read -r id name <<<"${all[$idx]}"
    if is_installed "$id"; then
      echo -e "  ${YELLOW}⊘${NC} ${name} — zaten yüklü"
    else
      urls+=("$(get_extension_url "$id")")
      echo -e "  ${BLUE}+${NC} ${name}"
    fi
  done

  echo
  if ((${#urls[@]})); then
    echo -e "${CYAN}${#urls[@]} sayfa '${TARGET}' profilinde açılıyor.${NC}"
    open_urls_in_target "${urls[@]}"
  else
    echo -e "${GREEN}Açılacak yeni eklenti yok.${NC}"
  fi
}

# =============================================================================
# Menü / Ana program
# =============================================================================

show_menu() {
  echo
  print_separator
  echo -e "${YELLOW}${BOLD}Hedef profil: ${GREEN}${TARGET}${NC}   ${CYAN}(${ISOLATED_ROOT}/${TARGET})${NC}"
  print_separator
  echo -e "${CYAN} 1)${NC} ${BOLD}Tüm Core'u kur${NC}"
  echo -e "${CYAN} 2)${NC} Çeviri araçları"
  echo -e "${CYAN} 3)${NC} Güvenlik & gizlilik"
  echo -e "${CYAN} 4)${NC} Navigasyon & prodüktivite"
  echo -e "${CYAN} 5)${NC} Medya"
  echo -e "${CYAN} 6)${NC} ${BOLD}Kripto cüzdanları${NC}"
  echo -e "${CYAN} 7)${NC} ${BOLD}Tema eklentileri${NC}"
  echo -e "${CYAN} 8)${NC} ${GREEN}Sadece eksikleri kur${NC} (önerilen)"
  echo -e "${CYAN} 9)${NC} ${MAGENTA}Başka profilden kopyala${NC} (fzf)"
  echo -e "${CYAN}10)${NC} Durum (katalog vs hedef)"
  echo -e "${CYAN}11)${NC} Katalog listesi"
  echo -e "${CYAN}12)${NC} İnteraktif seçim"
  echo -e "${CYAN}13)${NC} ${YELLOW}Hedef profili değiştir${NC}"
  echo -e "${CYAN} 0)${NC} ${RED}Çıkış${NC}"
  print_separator
}

main() {
  [[ -d "$ISOLATED_ROOT" ]] || {
    echo -e "${RED}${BOLD}❌ İzole profil dizini yok:${NC} $ISOLATED_ROOT" >&2
    echo -e "${YELLOW}İpucu:${NC} izole bir Brave profilini en az bir kez başlat (örn. start-brave-kenp)." >&2
    exit 1
  }

  select_target "${1:-}"
  print_banner

  while true; do
    show_menu
    local choice
    read -r -p "Seçiminiz (0-13): " choice
    case "$choice" in
    1) install_list "Core (tümü)" "${CORE_EXTENSIONS[@]}" ;;
    2) install_translation ;;
    3) install_security ;;
    4) install_productivity ;;
    5) install_media ;;
    6) install_list "Kripto Cüzdanları" "${CRYPTO_EXTENSIONS[@]}" ;;
    7) install_list "Tema Extensions" "${THEME_EXTENSIONS[@]}" ;;
    8) install_missing ;;
    9) copy_from_profile ;;
    10) show_status ;;
    11) show_list ;;
    12) interactive_install ;;
    13) select_target ;;
    0) echo -e "\n${GREEN}${BOLD}👋 İyi günler!${NC}"; exit 0 ;;
    *) echo -e "${RED}❌ Geçersiz seçim: $choice${NC}" ;;
    esac
    echo
    read -r -p "Devam etmek için Enter'a basın..." _
  done
}

main "$@"
