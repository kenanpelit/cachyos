#!/usr/bin/env bash
# ==============================================================================
# Script: firefoxctl.sh
# Description: Slim Firefox management for the native multi-profile setup
#              (~/.mozilla/firefox, launched with `firefox -P <profile>`).
#              The Firefox analog of bravectl/heliumctl — but Firefox has no
#              isolated-profile "engine" (it does -P natively) and no Chrome Web
#              Store extension catalog (Firefox uses AMO/.xpi), so there is no
#              `ext` subcommand and no profile_firefox.
#
# Subcommands:
#   firefoxctl launch <profile> [args...]  Launch via start-firefox-* / firefox -P
#   firefoxctl default [url...]            Open url(s) in the kenp profile
#   firefoxctl kill [opts]                 Kill Firefox processes
#   firefoxctl clean [opts]                Reclaim disk (cache2 + regenerable dirs)
#   firefoxctl list                        List profiles.ini profiles (+running)
#   firefoxctl help
#
# As $BROWSER: `firefoxctl <url>` is treated as `firefoxctl default <url>`.
# ==============================================================================

set -uo pipefail

# =============================================================================
# Config & colors
# =============================================================================
FF_HOME="${FIREFOX_HOME:-$HOME/.mozilla/firefox}"
FF_CACHE="${FIREFOX_CACHE:-${XDG_CACHE_HOME:-$HOME/.cache}/mozilla/firefox}"
PROFILES_INI="$FF_HOME/profiles.ini"
DEFAULT_PROFILE="${FIREFOX_DEFAULT_PROFILE:-kenp}"

if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
  RED=$'\033[0;31m'; GREEN=$'\033[0;32m'; YELLOW=$'\033[1;33m'
  BLUE=$'\033[0;34m'; CYAN=$'\033[0;36m'; BOLD=$'\033[1m'; NC=$'\033[0m'
else
  RED=''; GREEN=''; YELLOW=''; BLUE=''; CYAN=''; BOLD=''; NC=''
fi

die()  { printf '%b✗%b %s\n' "$RED" "$NC" "$*" >&2; exit 1; }
info() { printf '%bℹ%b %s\n' "$BLUE" "$NC" "$*"; }
ok()   { printf '%b✓%b %s\n' "$GREEN" "$NC" "$*"; }
warn() { printf '%b⚠%b %s\n' "$YELLOW" "$NC" "$*"; }

resolve_firefox() {
  local c
  for c in "${FIREFOX_BIN:-}" firefox firefox-bin /usr/lib/firefox/firefox; do
    [[ -n "$c" ]] || continue
    command -v "$c" >/dev/null 2>&1 && { command -v "$c"; return 0; }
    [[ -x "$c" ]] && { printf '%s\n' "$c"; return 0; }
  done
  return 1
}

# Parse profiles.ini → "Name<TAB>Path" lines.
profiles_list() {
  [[ -f "$PROFILES_INI" ]] || return 0
  awk -F= '
    /^\[Profile/   { name=""; path="" }
    /^Name=/       { name=substr($0,6) }
    /^Path=/       { path=substr($0,6); if (name != "") print name "\t" path }
  ' "$PROFILES_INI" | sort
}

# Resolve a profile Name to its on-disk Path (falls back to the name itself).
profile_path() {
  local name="$1" p
  p="$(profiles_list | awk -F'\t' -v n="$name" '$1==n{print $2; exit}')"
  printf '%s\n' "${p:-$name}"
}

profile_running() {
  # Anchor on `firefox` so brave/helium windows that share --class/--name
  # (e.g. --class=ai) are not counted as a running Firefox profile.
  local name="$1"
  pgrep -f -- "firefox.*(-P|--name|--class)[= ]${name}([[:space:]]|$)" >/dev/null 2>&1
}

# =============================================================================
# launch / default / list
# =============================================================================
cmd_launch() {
  (($#)) || die "kullanım: firefoxctl launch <profil> [args...]"
  local profile="$1"; shift
  if command -v "start-firefox-$profile" >/dev/null 2>&1; then
    exec "start-firefox-$profile" "$@"
  fi
  local ff; ff="$(resolve_firefox)" || die "firefox bulunamadı"
  exec "$ff" -P "$profile" --name "$profile" --class "$profile" --new-window --new-instance "$@"
}

cmd_default() {
  if command -v "start-firefox-$DEFAULT_PROFILE" >/dev/null 2>&1; then
    "start-firefox-$DEFAULT_PROFILE" "$@" >/dev/null 2>&1 &
    disown 2>/dev/null || true
    return 0
  fi
  local ff; ff="$(resolve_firefox)" || die "firefox bulunamadı"
  if (($#)); then "$ff" -P "$DEFAULT_PROFILE" --new-tab "$@" >/dev/null 2>&1 &
  else "$ff" -P "$DEFAULT_PROFILE" >/dev/null 2>&1 & fi
  disown 2>/dev/null || true
}

cmd_list() {
  [[ -f "$PROFILES_INI" ]] || die "profiles.ini yok: $PROFILES_INI"
  printf '%bFirefox profilleri%b (%s):\n' "$BOLD" "$NC" "$FF_HOME"
  local name path mark
  while IFS=$'\t' read -r name path; do
    [[ -n "$name" ]] || continue
    if profile_running "$name"; then mark="${GREEN}●${NC} çalışıyor"; else mark="${NC}○ kapalı"; fi
    printf '  %-20s %b  %b(%s)%b\n' "$name" "$mark" "$CYAN" "$path" "$NC"
  done < <(profiles_list)
}

# =============================================================================
# kill
# =============================================================================
# Pattern matches the firefox binary; own PID excluded so firefoxctl never
# matches/kills itself.
kill_find() {
  local filter="${1:-}" pat
  if [[ -n "$filter" ]]; then
    pat="firefox.*(-P|--name|--class)[= ]${filter}([[:space:]]|$)"
  else
    # firefox as an actual command (".../firefox -…"), not the substring
    # "firefox" inside some other cmdline (a shell, an editor, firefoxctl…).
    pat="(/|^)firefox[ -]"
  fi
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
firefoxctl kill [--profile=AD] [--force] [--timeout=SN] [--dry-run]
  Firefox süreçlerini kapatır (önce SIGTERM, kalırsa SIGKILL).
EOF
        return 0 ;;
      *) die "kill: bilinmeyen seçenek: $1" ;;
    esac
    shift
  done
  [[ "$timeout" =~ ^[0-9]+$ ]] || die "geçersiz timeout: $timeout"

  local pids; pids="$(kill_find "$filter")"
  if [[ -z "$pids" ]]; then info "Çalışan Firefox süreci yok${filter:+ ($filter)}"; return 0; fi
  local count; count="$(printf '%s\n' "$pids" | wc -l)"
  info "${count} Firefox süreci bulundu${filter:+ (profil: $filter)}"

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

  if [[ -z "$(kill_find "$filter")" ]]; then ok "Tüm Firefox süreçleri kapatıldı${filter:+ ($filter)}"
  else die "Bazı süreçler kapatılamadı"; fi
}

# =============================================================================
# clean — reclaim disk. Firefox disk cache lives OUTSIDE the profile, under
# ~/.cache/mozilla/firefox/<path> (cache2 is the big one); the profile dir also
# holds some regenerable caches. User data (places/cookies/key4/logins/storage
# defaults/extensions) is never touched.
# =============================================================================
clean_to_human() {
  if command -v numfmt >/dev/null 2>&1; then numfmt --to=iec-i --suffix=B "$1"; else echo "${1}B"; fi
}
clean_dir_bytes() {
  local t="$1"
  [[ -d "$t" ]] || { echo 0; return; }
  if du -sb -- "$t" >/dev/null 2>&1; then du -sb -- "$t" 2>/dev/null | awk '{print $1}'
  else du -sk -- "$t" 2>/dev/null | awk '{print $1 * 1024}'; fi
}

# Profile-dir caches that are safe to remove (regenerable / telemetry).
readonly -a FF_PROFILE_JUNK=(
  startupCache shader-cache OfflineCache crashes minidumps
  datareporting saved-telemetry-pings storage/temporary storage/to-be-removed
)

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
firefoxctl clean [--profile AD]... [--aggressive] [--force-close] [--yes]
  Firefox disk cache'ini (~/.cache/mozilla/firefox/<profil>) ve profildeki
  yeniden-üretilebilir dizinleri siler. Kullanıcı verisine (geçmiş, çerez,
  parola, eklenti) dokunmaz.
  --aggressive   sessionstore-backups (sekme kurtarma) da silinir.
  --force-close  Çalışan Firefox'u önce kapatır.
EOF
        return 0 ;;
      *) die "clean: bilinmeyen seçenek: $1" ;;
    esac
    shift
  done

  [[ -f "$PROFILES_INI" ]] || die "profiles.ini yok: $PROFILES_INI"

  if pgrep -x firefox >/dev/null 2>&1 || pgrep -f -- 'firefox.*-P ' >/dev/null 2>&1; then
    if $force_close; then
      warn "Firefox kapatılıyor…"; pkill -TERM -x firefox 2>/dev/null || true; sleep 3
      pkill -KILL -x firefox 2>/dev/null || true
    else
      die "Firefox çalışıyor. Kapat veya --force-close kullan (cache açıkken silmek riskli)."
    fi
  fi

  # Resolve target profiles → Name list
  local -a names=()
  if ((${#filters[@]})); then names=("${filters[@]}")
  else
    local n p
    while IFS=$'\t' read -r n p; do [[ -n "$n" ]] && names+=("$n"); done < <(profiles_list)
  fi
  ((${#names[@]})) || die "temizlenecek profil yok"

  if ! $yes; then
    echo "Hedef profiller: ${names[*]}"
    echo "Silinecek: ~/.cache/mozilla/firefox/<profil>/* (cache2 dahil) + profil içi"
    echo "  ${FF_PROFILE_JUNK[*]}"
    $aggressive && echo "  + sessionstore-backups (aggressive)"
    read -r -p "Devam? [y/N] " ans
    case "$ans" in y|Y|yes|YES|e|E|evet) ;; *) echo "İptal."; return 0 ;; esac
  fi

  local before after freed name path cdir pdir sub
  before=$(( $(clean_dir_bytes "$FF_CACHE") + $(clean_dir_bytes "$FF_HOME") ))
  for name in "${names[@]}"; do
    path="$(profile_path "$name")"
    cdir="$FF_CACHE/$path"
    pdir="$FF_HOME/$path"
    [[ -d "$pdir" ]] || { warn "profil dizini yok: $name ($path)"; continue; }
    # disk cache root is 100% regenerable → wipe its contents
    [[ -d "$cdir" ]] && find "$cdir" -mindepth 1 -maxdepth 1 -exec rm -rf {} + 2>/dev/null || true
    for sub in "${FF_PROFILE_JUNK[@]}"; do rm -rf "${pdir:?}/$sub" 2>/dev/null || true; done
    $aggressive && rm -rf "${pdir:?}/sessionstore-backups" 2>/dev/null || true
  done
  after=$(( $(clean_dir_bytes "$FF_CACHE") + $(clean_dir_bytes "$FF_HOME") ))
  freed=$((before - after)); ((freed < 0)) && freed=0
  ok "Önce: $(clean_to_human "$before")  Sonra: $(clean_to_human "$after")  Kurtarılan: $(clean_to_human "$freed")"
}

# =============================================================================
# help / dispatch
# =============================================================================
cmd_help() {
  cat <<EOF
${BOLD}firefoxctl${NC} — Firefox profil yönetimi (~/.mozilla/firefox, native -P)

${BOLD}Komutlar:${NC}
  launch <profil> [args]   start-firefox-* / firefox -P ile başlat
  default [url...]         url'leri ${DEFAULT_PROFILE} profilinde aç (\$BROWSER girişi)
  kill [seçenekler]        Firefox süreçlerini kapat (--profile= --force --dry-run)
  clean [seçenekler]       disk cache + yeniden-üretilebilir dizinleri temizle
  list                    profiles.ini profillerini listele (+çalışıyor mu)
  help                    bu yardım

${BOLD}Not:${NC} Firefox native -P kullanır; ayrı 'engine' (profile_firefox) ve Chrome
Web Store eklenti kataloğu (ext) yok — eklentiler AMO/.xpi üzerindendir.
EOF
}

main() {
  case "${1:-}" in
    launch)            shift; cmd_launch "$@" ;;
    default)           shift; cmd_default "$@" ;;
    kill)              shift; cmd_kill "$@" ;;
    clean)             shift; cmd_clean "$@" ;;
    list|ls)           shift; cmd_list "$@" ;;
    ""|help|-h|--help) cmd_help ;;
    *://*|magnet:*)    cmd_default "$@" ;;   # URL → \$BROWSER davranışı
    *)                 die "bilinmeyen komut: $1  (bkz: firefoxctl help)" ;;
  esac
}

main "$@"
