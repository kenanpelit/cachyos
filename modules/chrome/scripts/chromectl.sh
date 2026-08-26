#!/usr/bin/env bash
# ==============================================================================
# Script: chromectl.sh
# Description: Unified Chrome management for the isolated-profile setup
#              (~/.chrome). One entry point for kill / clean / ext / list around
#              the isolated Google Chrome profiles. The actual profile launcher
#              remains the separate `profile_chrome` engine, which chromectl
#              delegates to. (The Chrome analog of bravectl / heliumctl.)
#
# Subcommands:
#   chromectl launch <profile> [args...]   Launch via profile_chrome
#   chromectl default [url...]             Open url(s) in the kenp profile
#   chromectl kill [opts]                  Kill Chrome processes
#   chromectl clean [opts]                 Reclaim disk from isolated profiles
#   chromectl ext [profile]                Extension manager (catalog + copy)
#   chromectl list                         List isolated profiles (+running)
#   chromectl help
#
# As $BROWSER: `chromectl <url>` is treated as `chromectl default <url>`.
# ==============================================================================

set -uo pipefail   # NOT -e: the interactive `ext` menu relies on non-zero
                   # arithmetic/reads; other subcommands guard errors explicitly.

# =============================================================================
# Shared config & colors
# =============================================================================
readonly STORE_URL="https://chromewebstore.google.com/detail"
# profile_chrome stores each isolated profile directly under ~/.chrome/<class>
# (no intermediate "isolated" dir, unlike brave/helium). Honour the same
# ISOLATED_ROOT env override that profile_chrome reads, so the two stay in sync.
# ~/.chrome is often itself a symlink (e.g. -> /repo/archive/.chrome); the value
# is kept UN-resolved on purpose so it matches the --user-data-dir chrome is
# actually launched with (profile_chrome passes the symlink path verbatim, and
# our pgrep/kill/clean matching keys off it). Root-level directory listings use
# `find -L` so they still descend through that symlinked root.
ISOLATED_ROOT="${ISOLATED_ROOT:-$HOME/.chrome}"

if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
  RED=$'\033[0;31m'; GREEN=$'\033[0;32m'; YELLOW=$'\033[1;33m'
  BLUE=$'\033[0;34m'; MAGENTA=$'\033[0;35m'; CYAN=$'\033[0;36m'
  BOLD=$'\033[1m'; NC=$'\033[0m'
else
  RED=''; GREEN=''; YELLOW=''; BLUE=''; MAGENTA=''; CYAN=''; BOLD=''; NC=''
fi

die()  { printf '%b✗%b %s\n' "$RED" "$NC" "$*" >&2; exit 1; }
info() { printf '%bℹ%b %s\n' "$BLUE" "$NC" "$*"; }
ok()   { printf '%b✓%b %s\n' "$GREEN" "$NC" "$*"; }
warn() { printf '%b⚠%b %s\n' "$YELLOW" "$NC" "$*"; }

# Resolve the profile_chrome engine.
resolve_profile_chrome() {
  local script_dir candidate
  script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
  for candidate in \
    "${script_dir}/profile_chrome" \
    "${HOME}/.local/bin/profile_chrome" \
    "/usr/local/bin/profile_chrome" \
    "profile_chrome"; do
    command -v "$candidate" >/dev/null 2>&1 && { command -v "$candidate"; return 0; }
  done
  return 1
}

# Resolve a raw chrome binary (last-resort fallback).
resolve_chrome_binary() {
  local c
  for c in "${CHROME_BIN:-}" google-chrome-stable google-chrome chrome /opt/google/chrome/chrome; do
    [[ -n "$c" ]] || continue
    command -v "$c" >/dev/null 2>&1 && { command -v "$c"; return 0; }
  done
  return 1
}

# List isolated profile directory names.
profiles_list() {
  find -L "$ISOLATED_ROOT" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' 2>/dev/null | sort
}

# =============================================================================
# launch / default / list
# =============================================================================
cmd_launch() {
  (($#)) || die "kullanım: chromectl launch <profil> [args...]"
  local pb; pb="$(resolve_profile_chrome)" || die "profile_chrome bulunamadı"
  exec "$pb" "$@"
}

cmd_default() {
  local pb
  if pb="$(resolve_profile_chrome)"; then
    if (($#)); then
      "$pb" kenp --separate --new-tab "$@"
    else
      "$pb" kenp --separate
    fi
    return 0
  fi
  # Fallback: raw chrome on its default profile.
  local bin; bin="$(resolve_chrome_binary)" || die "profile_chrome ve chrome bulunamadı"
  exec "$bin" --profile-directory=Default "$@"
}

cmd_list() {
  [[ -d "$ISOLATED_ROOT" ]] || die "izole profil dizini yok: $ISOLATED_ROOT"
  printf '%bChrome izole profilleri%b (%s):\n' "$BOLD" "$NC" "$ISOLATED_ROOT"
  local p mark
  while IFS= read -r p; do
    [[ -n "$p" ]] || continue
    if pgrep -f -- "--user-data-dir=$ISOLATED_ROOT/$p" >/dev/null 2>&1; then
      mark="${GREEN}●${NC} çalışıyor"
    else
      mark="${NC}○ kapalı"
    fi
    printf '  %-28s %b\n' "$p" "$mark"
  done < <(profiles_list)
}

# =============================================================================
# kill  (eski chrome_killer)
# =============================================================================
kill_find() {
  local filter="${1:-}" pat
  # Anchor on the Google Chrome binary path so a bare "chrome" match never
  # catches chromium, other Chromium-based apps, or chromectl itself.
  if [[ -n "$filter" ]]; then
    pat="/opt/google/chrome/chrome.*(user-data-dir|profile-directory).*$filter"
  else
    pat="/opt/google/chrome/chrome"
  fi
  # Drop chromectl's own PID so `kill` never SIGTERMs itself mid-run.
  pgrep -f -- "$pat" 2>/dev/null | grep -vxF "$$" || true
}

cmd_kill() {
  local filter="" force=false timeout=5 dry=false
  while (($#)); do
    case "$1" in
      --profile=*) filter="${1#*=}" ;;
      --profile)   shift; filter="${1:-}" ;;
      --force)     force=true ;;
      --timeout=*) timeout="${1#*=}" ;;
      --dry-run)   dry=true ;;
      -h|--help)
        cat <<EOF
chromectl kill [--profile=AD] [--force] [--timeout=SN] [--dry-run]
  Chrome süreçlerini kapatır (önce SIGTERM, kalırsa SIGKILL).
EOF
        return 0 ;;
      *) die "kill: bilinmeyen seçenek: $1" ;;
    esac
    shift
  done
  [[ "$timeout" =~ ^[0-9]+$ ]] || die "geçersiz timeout: $timeout"

  local pids; pids="$(kill_find "$filter")"
  if [[ -z "$pids" ]]; then info "Çalışan Chrome süreci yok${filter:+ ($filter)}"; return 0; fi
  local count; count="$(printf '%s\n' "$pids" | wc -l)"
  info "${count} Chrome süreci bulundu${filter:+ (profil: $filter)}"

  if $dry; then info "DRY-RUN — PID'ler: $(printf '%s' "$pids" | tr '\n' ' ')"; return 0; fi

  if $force; then
    warn "Zorla kapatılıyor (SIGKILL)…"
    printf '%s\n' "$pids" | xargs -r kill -9 2>/dev/null || true
    sleep 2
  else
    info "SIGTERM gönderiliyor, ${timeout}s bekleniyor…"
    printf '%s\n' "$pids" | xargs -r kill -15 2>/dev/null || true
    sleep "$timeout"
    local left; left="$(kill_find "$filter")"
    if [[ -n "$left" ]]; then
      warn "Kalanlar zorla kapatılıyor…"
      printf '%s\n' "$left" | xargs -r kill -9 2>/dev/null || true
      sleep 2
    fi
  fi

  if [[ -z "$(kill_find "$filter")" ]]; then ok "Tüm Chrome süreçleri kapatıldı${filter:+ ($filter)}"
  else die "Bazı süreçler kapatılamadı"; fi
}

# =============================================================================
# clean  (eski cleanup_chrome_profiles)
# =============================================================================
clean_to_human() {
  if command -v numfmt >/dev/null 2>&1; then numfmt --to=iec-i --suffix=B "$1"; else echo "${1}B"; fi
}

clean_dir_bytes() {
  local t="$1"
  if du -sb -- "$t" >/dev/null 2>&1; then du -sb -- "$t" 2>/dev/null | awk '{print $1}'
  else du -sk -- "$t" 2>/dev/null | awk '{print $1 * 1024}'; fi
}

clean_running_pids() {
  local root="$1"
  ps -eo pid=,args= | awk -v dir="$root" '
    { pid=$1; $1=""; sub(/^[[:space:]]+/,"",$0); cmd=$0
      if (cmd !~ /(^|[[:space:]])([^[:space:]]*\/)?chrome([[:space:]]|$)/) next
      if (index(cmd, "--user-data-dir=" dir) || index(cmd, "--user-data-dir " dir)) print pid }'
}

cmd_clean() {
  local aggressive=false force_close=false yes=false
  local -a filters=()
  while (($#)); do
    case "$1" in
      --profile)    shift; [[ -n "${1:-}" ]] || die "clean: --profile değeri eksik"; filters+=("$1") ;;
      --profile=*)  filters+=("${1#*=}") ;;
      --aggressive) aggressive=true ;;
      --force-close) force_close=true ;;
      --yes|-y)     yes=true ;;
      -h|--help)
        cat <<EOF
chromectl clean [--profile AD]... [--aggressive] [--force-close] [--yes]
  İzole profillerden cache/yedek dizinlerini siler (kullanıcı verisine dokunmaz).
  --aggressive   Service Worker klasörlerini de siler.
  --force-close  Çalışan eşleşen Chrome süreçlerini otomatik kapatır.
EOF
        return 0 ;;
      *) die "clean: bilinmeyen seçenek: $1" ;;
    esac
    shift
  done

  [[ -d "$ISOLATED_ROOT" ]] || die "izole profil dizini yok: $ISOLATED_ROOT"

  local running; running="$(clean_running_pids "$ISOLATED_ROOT" || true)"
  if [[ -n "$running" ]]; then
    if $force_close; then
      printf '%s\n' "$running" | xargs -r kill -TERM; sleep 2
      local rem; rem="$(clean_running_pids "$ISOLATED_ROOT" || true)"
      [[ -n "$rem" ]] && { printf '%s\n' "$rem" | xargs -r kill -KILL; }
    else
      die "İzole Chrome profilleri çalışıyor. Kapat veya --force-close kullan."
    fi
  fi

  # Hedef profil dizinleri
  local -a targets=()
  if ((${#filters[@]})); then
    local f
    for f in "${filters[@]}"; do
      [[ -d "$ISOLATED_ROOT/$f" ]] && targets+=("$ISOLATED_ROOT/$f") || warn "profil yok: $f"
    done
  else
    local d
    while IFS= read -r d; do targets+=("$d"); done \
      < <(find -L "$ISOLATED_ROOT" -mindepth 1 -maxdepth 1 -type d 2>/dev/null)
  fi
  ((${#targets[@]})) || die "temizlenecek profil yok"

  if ! $yes; then
    echo "Hedef: ${targets[*]##*/}"
    echo "Silinecek: *.bak-* yedekleri + cache klasörleri (Cache, Code Cache, GPUCache,"
    echo "  GrShaderCache, ShaderCache, Dawn*Cache, Graphite*, *_crx_cache)"
    $aggressive && echo "  + Service Worker (aggressive)"
    read -r -p "Devam? [y/N] " ans
    case "$ans" in y|Y|yes|YES|e|E|evet) ;; *) echo "İptal."; return 0 ;; esac
  fi

  local before after freed t
  before="$(clean_dir_bytes "$ISOLATED_ROOT")"
  for t in "${targets[@]}"; do
    find "$t" -maxdepth 1 -mindepth 1 -type d -name '*.bak-*' -exec rm -rf {} + 2>/dev/null || true
    find "$t" -type d \
      \( -name 'Cache' -o -name 'Code Cache' -o -name 'GPUCache' -o -name 'GrShaderCache' \
         -o -name 'ShaderCache' -o -name 'DawnGraphiteCache' -o -name 'DawnWebGPUCache' \
         -o -name 'GraphiteDawnCache' -o -name 'component_crx_cache' \
         -o -name 'extensions_crx_cache' \) \
      -exec rm -rf {} + 2>/dev/null || true
    $aggressive && find "$t" -type d -name 'Service Worker' -exec rm -rf {} + 2>/dev/null || true
  done
  after="$(clean_dir_bytes "$ISOLATED_ROOT")"
  freed=$((before - after)); ((freed < 0)) && freed=0
  ok "Önce: $(clean_to_human "$before")  Sonra: $(clean_to_human "$after")  Kurtarılan: $(clean_to_human "$freed")"
}

# =============================================================================
# ext  (eski chrome-extensions / chrome-ext-copy) — interaktif eklenti yöneticisi
# =============================================================================
declare -a CORE_EXTENSIONS=(
  "aapbdbdomjkkjkaonfhkkikfgjllcleb:Google Translate"
  "cofdbpoegempjloogbagkncekinflcnj:DeepL"
  "ibplnjkanclpjokhdolnendpplpjiace:Simple Translate"
  "ddkjiahejlhfcafbddmgiahcphecmpfh:uBlock Origin Lite"
  "pkehgijcmpdhfbdbbnkijodmdjhbjlgp:Privacy Badger"
  "gfbliohnnapiefjpjlpjnehglfpaknnc:Surfingkeys"
  "eekailopagacbcdloonjhbiecobagjci:Go Back With Backspace"
  "inglelmldhjcljkomheneakjkpadclhf:Keep Awake"
  "kdejdkdjdoabfihpcjmgjebcpfbhepmh:Copy Link Address"
  "kgfcmiijchdkbknmjnojfngnapkibkdh:Picture-in-Picture"
  "mbcjcnomlakhkechnbhmfjhnnllpbmlh:Tab Pinner"
  "lmjnegcaeklhafolokijcfjliaokphfk:Video DownloadHelper"
  "ponfpcnoihfmfllpaingbgckeeldkhle:Enhancer for YouTube"
  "gphhapmejobijbbhgpjhcjognlahblep:GNOME Shell Integration"
  "njbclohenpagagafbmdipcdoogfpnfhp:Ethereum Gas Prices"
)
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
declare -a THEME_EXTENSIONS=(
  "eimadpbcbfnmbkopoojfekhnkhdbieeh:Dark Reader"
  "clngdbkpkpeebahjckkjfobafhncgmne:Stylus"
  "bkkmolkhemgaeaeggcmfbghljjjoofoh:Catppuccin Mocha"
)

EXT_TARGET=""
EXT_DIR=""

ext_url() { echo "${STORE_URL}/$1"; }
ext_is_installed() { [[ -d "$EXT_DIR/$1" ]]; }
ext_version() { ext_is_installed "$1" || { echo ""; return; }; ls -1 "$EXT_DIR/$1" 2>/dev/null | sort -V | tail -n1; }

ext_count() {
  local -n _arr="$1"; local c=0 entry id
  for entry in "${_arr[@]}"; do id="${entry%%:*}"; ext_is_installed "$id" && ((c++)); done
  echo "$c"
}

ext_set_target() { EXT_DIR="$ISOLATED_ROOT/$EXT_TARGET/Default/Extensions"; }

ext_select_target() {
  local want="${1:-}"
  local -a profiles
  mapfile -t profiles < <(profiles_list)
  ((${#profiles[@]})) || die "izole profil yok: $ISOLATED_ROOT"
  if [[ -n "$want" ]]; then
    local p
    for p in "${profiles[@]}"; do [[ "$p" == "$want" ]] && { EXT_TARGET="$want"; ext_set_target; return; }; done
    warn "'$want' profili yok; listeden seç."
  fi
  if command -v fzf >/dev/null 2>&1; then
    EXT_TARGET="$(printf '%s\n' "${profiles[@]}" | fzf --no-multi --height=40% --reverse --prompt='Hedef profil > ')"
  else
    local i=1 p n
    for p in "${profiles[@]}"; do printf "%2d) %s\n" "$i" "$p"; ((i++)); done
    read -r -p "Hedef profil no: " n
    [[ "$n" =~ ^[0-9]+$ ]] && EXT_TARGET="${profiles[$((n - 1))]:-}"
  fi
  [[ -n "$EXT_TARGET" ]] || { echo "Hedef seçilmedi."; exit 0; }
  ext_set_target
}

ext_open() {
  local urls=("$@"); ((${#urls[@]})) || return 0
  if command -v "start-chrome-$EXT_TARGET" >/dev/null 2>&1; then
    "start-chrome-$EXT_TARGET" "${urls[@]}" >/dev/null 2>&1 &
  else
    local bin; bin="$(resolve_chrome_binary || true)"
    [[ -n "$bin" ]] || { warn "start-chrome-$EXT_TARGET ve chrome bulunamadı."; return 1; }
    "$bin" --user-data-dir="$ISOLATED_ROOT/$EXT_TARGET" --profile-directory=Default "${urls[@]}" >/dev/null 2>&1 &
  fi
  disown 2>/dev/null || true
}

# resolve a source-profile extension's display name
ext_resolve_name() {
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
        msg="$(jq -r --arg k "$key" '.[$k].message // empty' "$extdir/$ver/_locales/$l/messages.json" 2>/dev/null)"
        [[ -n "$msg" ]] && { printf '%s' "$msg"; return; }
      done
    fi
  fi
  printf '%s' "${name:-$id}"
}

ext_install_list() {
  local category="$1"; shift
  local -a items=("$@")
  printf '%b🚀 %s → %s%b\n\n' "$MAGENTA$BOLD" "$category" "$EXT_TARGET" "$NC"
  local urls=() opened=0 skipped=0 entry id name
  for entry in "${items[@]}"; do
    IFS=':' read -r id name <<<"$entry"
    if ext_is_installed "$id"; then
      printf '  %b✓%b %s %b(v%s)%b — zaten yüklü\n' "$GREEN" "$NC" "$name" "$CYAN" "$(ext_version "$id")" "$NC"
      ((skipped++))
    else
      printf '  %b+%b %s\n' "$BLUE" "$NC" "$name"
      urls+=("$(ext_url "$id")"); ((opened++))
    fi
  done
  echo
  if ((${#urls[@]})); then
    printf '%b%d Web Store sayfası '\''%s'\'' profilinde açılıyor — her birinde "Add to Chrome" tıkla.%b\n' "$CYAN" "${#urls[@]}" "$EXT_TARGET" "$NC"
    ext_open "${urls[@]}"
  else
    printf '%bHepsi zaten yüklü.%b\n' "$GREEN" "$NC"
  fi
  printf '%bAçılan:%b %d  %bAtlanan:%b %d\n' "$CYAN" "$NC" "$opened" "$CYAN" "$NC" "$skipped"
}

ext_install_missing() {
  printf '%b🔍 Eksik eklentiler (core + tema) → %s%b\n\n' "$MAGENTA$BOLD" "$EXT_TARGET" "$NC"
  local -a missing=() entry id name
  for entry in "${CORE_EXTENSIONS[@]}" "${THEME_EXTENSIONS[@]}"; do
    IFS=':' read -r id name <<<"$entry"; ext_is_installed "$id" || missing+=("$entry")
  done
  ((${#missing[@]})) || { printf '%b✅ Tümü yüklü.%b\n' "$GREEN$BOLD" "$NC"; return 0; }
  ext_install_list "Eksik Eklentiler" "${missing[@]}"
}

ext_copy() {
  command -v fzf >/dev/null 2>&1 || { warn "fzf gerekli."; return 1; }
  command -v jq  >/dev/null 2>&1 || { warn "jq gerekli."; return 1; }
  local -a profiles
  mapfile -t profiles < <(profiles_list | grep -vx "$EXT_TARGET")
  ((${#profiles[@]})) || { warn "Kaynak için başka profil yok."; return 1; }
  local source
  source="$(printf '%s\n' "${profiles[@]}" | fzf --no-multi --height=40% --reverse --prompt="Kaynak profil (→ $EXT_TARGET) > ")"
  [[ -n "$source" ]] || { echo "Kaynak seçilmedi."; return 0; }
  local src_pref="$ISOLATED_ROOT/$source/Default/Preferences"
  local src_ext="$ISOLATED_ROOT/$source/Default/Extensions"
  [[ -d "$src_ext" ]] || { warn "Kaynak eklentileri yok: $src_ext"; return 1; }
  local items=() d id
  for d in "$src_ext"/*/; do
    id="$(basename "$d")"; [[ "$id" == "Temp" ]] && continue
    [[ "$id" =~ ^[a-p]{32}$ ]] || continue
    items+=("$id"$'\t'"$(ext_resolve_name "$id" "$src_pref" "$src_ext")")
  done
  ((${#items[@]})) || { warn "'$source' içinde eklenti yok."; return 1; }
  local selected
  selected="$(printf '%s\n' "${items[@]}" | sort -f -t$'\t' -k2 \
    | fzf --multi --reverse --height=70% --with-nth=2.. --delimiter=$'\t' \
        --prompt="$source → $EXT_TARGET  (TAB çoklu, Enter onayla) > " \
        --header='Seçilenlerin Web Store sayfaları hedefte açılır; "Add" tıkla.')"
  [[ -n "$selected" ]] || { echo "Bir şey seçilmedi."; return 0; }
  local urls=() name
  while IFS=$'\t' read -r id name; do
    [[ -n "$id" ]] || continue
    if ext_is_installed "$id"; then printf '  %b✓%b %s — %s içinde zaten yüklü\n' "$GREEN" "$NC" "$name" "$EXT_TARGET"
    else urls+=("$(ext_url "$id")"); printf '  %b+%b %s\n' "$BLUE" "$NC" "$name"; fi
  done <<<"$selected"
  echo
  if ((${#urls[@]})); then printf '%b%d sayfa '\''%s'\'' profilinde açılıyor.%b\n' "$CYAN" "${#urls[@]}" "$EXT_TARGET" "$NC"; ext_open "${urls[@]}"
  else printf '%bSeçilenlerin hepsi zaten yüklü.%b\n' "$GREEN" "$NC"; fi
}

ext_status_section() {
  local -n _arr="$1"; local title="$2" entry id name
  printf '%b═══ %s (%d adet) ═══%b\n\n' "$CYAN$BOLD" "$title" "${#_arr[@]}" "$NC"
  for entry in "${_arr[@]}"; do
    IFS=':' read -r id name <<<"$entry"; printf "%-40s " "$name"
    if ext_is_installed "$id"; then printf '%b✓ Yüklü%b %b(v%s)%b\n' "$GREEN" "$NC" "$CYAN" "$(ext_version "$id")" "$NC"
    else printf '%b✗ Yüklü değil%b\n' "$RED" "$NC"; fi
  done
  printf '\n%bİstatistik:%b %b%s%b/%d yüklü\n\n' "$YELLOW" "$NC" "$GREEN" "$(ext_count "$1")" "$NC" "${#_arr[@]}"
}

ext_show_status() {
  printf '%b🔍 '\''%s'\'' profilinde eklenti durumu%b\n\n' "$MAGENTA$BOLD" "$EXT_TARGET" "$NC"
  ext_status_section CORE_EXTENSIONS "Core Extensions"
  ext_status_section CRYPTO_EXTENSIONS "Kripto Cüzdanları"
  ext_status_section THEME_EXTENSIONS "Tema Extensions"
  local total=$((${#CORE_EXTENSIONS[@]} + ${#CRYPTO_EXTENSIONS[@]} + ${#THEME_EXTENSIONS[@]}))
  local inst=$(( $(ext_count CORE_EXTENSIONS) + $(ext_count CRYPTO_EXTENSIONS) + $(ext_count THEME_EXTENSIONS) ))
  printf '%bTOPLAM (%s):%b %b%d%b/%d katalog eklentisi yüklü\n' "$BOLD" "$EXT_TARGET" "$NC" "$GREEN" "$inst" "$NC" "$total"
}

ext_show_list() {
  printf '%b📋 Katalog%b\n\n' "$MAGENTA$BOLD" "$NC"
  local grp title entry id name
  for grp in CORE_EXTENSIONS:"Core" CRYPTO_EXTENSIONS:"Kripto" THEME_EXTENSIONS:"Tema"; do
    local -n _a="${grp%%:*}"; title="${grp#*:}"
    printf '%b═══ %s (%d) ═══%b\n' "$CYAN$BOLD" "$title" "${#_a[@]}" "$NC"
    for entry in "${_a[@]}"; do IFS=':' read -r id name <<<"$entry"; printf '%-45s %b%-32s%b\n' "$name" "$BLUE" "$id" "$NC"; done
    echo
  done
}

ext_interactive() {
  printf '%b📋 İnteraktif seçim → %s%b\n\n' "$MAGENTA$BOLD" "$EXT_TARGET" "$NC"
  local -a all=("${CORE_EXTENSIONS[@]}" "${CRYPTO_EXTENSIONS[@]}" "${THEME_EXTENSIONS[@]}")
  local i=1 entry id name st
  for entry in "${all[@]}"; do
    IFS=':' read -r id name <<<"$entry"
    if ext_is_installed "$id"; then st="${GREEN}[Yüklü]${NC}"; else st="${RED}[Yok]${NC}"; fi
    printf '%b%2d)%b %-45s %b\n' "$CYAN" "$i" "$NC" "$name" "$st"; ((i++))
  done
  printf '\n%bSeçim:%b tekli '\''5'\'' · çoklu '\''1,3,5'\'' · aralık '\''1-5'\'' · '\''all'\''\n' "$GREEN$BOLD" "$NC"
  local selection; read -r -p "Seçiminiz: " selection; [[ -n "$selection" ]] || return 0
  local -a nums=()
  if [[ "$selection" == "all" ]]; then
    for ((n = 1; n <= ${#all[@]}; n++)); do nums+=("$n"); done
  else
    local part; IFS=',' read -ra parts <<<"$selection"
    for part in "${parts[@]}"; do
      part="$(echo "$part" | xargs)"
      if [[ "$part" =~ ^([0-9]+)-([0-9]+)$ ]]; then for ((n = BASH_REMATCH[1]; n <= BASH_REMATCH[2]; n++)); do nums+=("$n"); done
      elif [[ "$part" =~ ^[0-9]+$ ]]; then nums+=("$part"); fi
    done
  fi
  local urls=() num idx
  for num in "${nums[@]}"; do
    ((num >= 1 && num <= ${#all[@]})) || continue
    idx=$((num - 1)); IFS=':' read -r id name <<<"${all[$idx]}"
    if ext_is_installed "$id"; then printf '  %b⊘%b %s — zaten yüklü\n' "$YELLOW" "$NC" "$name"
    else urls+=("$(ext_url "$id")"); printf '  %b+%b %s\n' "$BLUE" "$NC" "$name"; fi
  done
  echo
  if ((${#urls[@]})); then printf '%b%d sayfa '\''%s'\'' profilinde açılıyor.%b\n' "$CYAN" "${#urls[@]}" "$EXT_TARGET" "$NC"; ext_open "${urls[@]}"
  else printf '%bAçılacak yeni eklenti yok.%b\n' "$GREEN" "$NC"; fi
}

ext_menu() {
  printf '\n%b═══════════════════════════════════════════════════%b\n' "$CYAN" "$NC"
  printf '%bHedef profil: %b%s%b   %b(%s)%b\n' "$YELLOW$BOLD" "$GREEN" "$EXT_TARGET" "$NC" "$CYAN" "$ISOLATED_ROOT/$EXT_TARGET" "$NC"
  printf '%b═══════════════════════════════════════════════════%b\n' "$CYAN" "$NC"
  cat <<EOF
 1) Tüm Core'u kur          7) Tema eklentileri
 2) Çeviri araçları         8) Sadece eksikleri kur (önerilen)
 3) Güvenlik & gizlilik     9) Başka profilden kopyala (fzf)
 4) Navigasyon & prod.     10) Durum (katalog vs hedef)
 5) Medya                  11) Katalog listesi
 6) Kripto cüzdanları      12) İnteraktif seçim
                           13) Hedef profili değiştir
 0) Çıkış
EOF
}

cmd_ext() {
  [[ -d "$ISOLATED_ROOT" ]] || die "izole profil dizini yok: $ISOLATED_ROOT (önce bir profili başlat)"
  ext_select_target "${1:-}"
  while true; do
    ext_menu
    local choice; read -r -p "Seçiminiz (0-13): " choice
    case "$choice" in
      1) ext_install_list "Core (tümü)" "${CORE_EXTENSIONS[@]}" ;;
      2) ext_install_list "Çeviri" \
           "aapbdbdomjkkjkaonfhkkikfgjllcleb:Google Translate" \
           "cofdbpoegempjloogbagkncekinflcnj:DeepL" \
           "ibplnjkanclpjokhdolnendpplpjiace:Simple Translate" ;;
      3) ext_install_list "Güvenlik & Gizlilik" \
           "ddkjiahejlhfcafbddmgiahcphecmpfh:uBlock Origin Lite" \
           "pkehgijcmpdhfbdbbnkijodmdjhbjlgp:Privacy Badger" ;;
      4) ext_install_list "Navigasyon & Prodüktivite" \
           "gfbliohnnapiefjpjlpjnehglfpaknnc:Surfingkeys" \
           "eekailopagacbcdloonjhbiecobagjci:Go Back With Backspace" \
           "inglelmldhjcljkomheneakjkpadclhf:Keep Awake" \
           "kdejdkdjdoabfihpcjmgjebcpfbhepmh:Copy Link Address" \
           "kgfcmiijchdkbknmjnojfngnapkibkdh:Picture-in-Picture" \
           "mbcjcnomlakhkechnbhmfjhnnllpbmlh:Tab Pinner" ;;
      5) ext_install_list "Medya" \
           "lmjnegcaeklhafolokijcfjliaokphfk:Video DownloadHelper" \
           "ponfpcnoihfmfllpaingbgckeeldkhle:Enhancer for YouTube" ;;
      6) ext_install_list "Kripto Cüzdanları" "${CRYPTO_EXTENSIONS[@]}" ;;
      7) ext_install_list "Tema Extensions" "${THEME_EXTENSIONS[@]}" ;;
      8) ext_install_missing ;;
      9) ext_copy ;;
      10) ext_show_status ;;
      11) ext_show_list ;;
      12) ext_interactive ;;
      13) ext_select_target ;;
      0) printf '\n%b👋 İyi günler!%b\n' "$GREEN$BOLD" "$NC"; return 0 ;;
      *) printf '%b❌ Geçersiz seçim: %s%b\n' "$RED" "$choice" "$NC" ;;
    esac
    echo; read -r -p "Devam etmek için Enter'a basın..." _
  done
}

# =============================================================================
# help / dispatch
# =============================================================================
cmd_help() {
  cat <<EOF
${BOLD}chromectl${NC} — Chrome izole-profil yönetimi (~/.chrome/isolated)

${BOLD}Komutlar:${NC}
  launch <profil> [args]   profile_chrome ile başlat
  default [url...]         url'leri kenp profilinde aç (\$BROWSER girişi)
  kill [seçenekler]        Chrome süreçlerini kapat (--profile= --force --dry-run)
  clean [seçenekler]       izole profillerden cache/yedek temizle (--aggressive --yes)
  ext [profil]            eklenti yöneticisi (katalog + profilden kopyala)
  list                    izole profilleri listele (+çalışıyor mu)
  help                    bu yardım

${BOLD}Notlar:${NC}
  • profile_chrome ayrı bir 'motor'dur; chromectl ona delege eder.
  • \$BROWSER olarak: 'chromectl <url>' → 'chromectl default <url>'.
EOF
}

main() {
  case "${1:-}" in
    launch)            shift; cmd_launch "$@" ;;
    default)           shift; cmd_default "$@" ;;
    kill)              shift; cmd_kill "$@" ;;
    clean)             shift; cmd_clean "$@" ;;
    ext|extensions)    shift; cmd_ext "$@" ;;
    list|ls)           shift; cmd_list "$@" ;;
    ""|help|-h|--help) cmd_help ;;
    *://*|magnet:*)    cmd_default "$@" ;;   # URL → \$BROWSER davranışı
    *)                 die "bilinmeyen komut: $1  (bkz: chromectl help)" ;;
  esac
}

main "$@"
