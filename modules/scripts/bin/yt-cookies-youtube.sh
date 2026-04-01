#!/usr/bin/env bash
# ==============================================================================
# Script: yt-cookies-youtube.sh
# Description: Export and validate YouTube cookies in Netscape format via yt-dlp.
# ==============================================================================
set -euo pipefail

DEFAULT_OUTPUT="${XDG_CONFIG_HOME:-$HOME/.config}/yt-dlp/cookies-youtube.txt"
DEFAULT_TEST_URL="${YT_COOKIES_TEST_URL:-https://www.youtube.com/watch?v=dQw4w9WgXcQ}"
YTDLP_BIN="${YTDLP_BIN:-yt-dlp}"
TRY_EXPORT_TIMEOUT="${YT_COOKIES_TRY_TIMEOUT:-8}"

quiet=false
mode="export"
force=false
output_file="$DEFAULT_OUTPUT"
test_url="$DEFAULT_TEST_URL"

log() {
  $quiet && return 0
  printf '%s\n' "$*" >&2
}

die() {
  printf 'yt-cookies-youtube: %s\n' "$*" >&2
  exit 1
}

usage() {
  cat <<'EOF'
Usage: yt-cookies-youtube [options]

Exports fresh YouTube cookies in Netscape format using yt-dlp's browser extraction.
Helium/Chromium roots are tried first, then Brave roots as fallback.

Options:
  --output PATH   Write cookies to PATH
  --url URL       Test URL used during extraction
  --check         Validate an existing cookies file instead of exporting
  --print-source  Print the first working browser cookie source and exit
  --print-sources Print all working browser cookie sources and exit
  --force         Refresh even if the target file already looks valid
  --quiet         Reduce log output
  -h, --help      Show this help

Examples:
  yt-cookies-youtube
  yt-cookies-youtube --output ~/.local/state/yt-dlp/cookies-youtube.txt
  yt-cookies-youtube --check
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --output)
      [[ $# -ge 2 ]] || die "--output requires a path"
      output_file="$2"
      shift 2
      ;;
    --url)
      [[ $# -ge 2 ]] || die "--url requires a value"
      test_url="$2"
      shift 2
      ;;
    --check)
      mode="check"
      shift
      ;;
    --print-source)
      mode="source"
      shift
      ;;
    --print-sources)
      mode="sources"
      shift
      ;;
    --force)
      force=true
      shift
      ;;
    --quiet)
      quiet=true
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "unknown argument: $1"
      ;;
  esac
done

have_youtube_login_cookies() {
  local file="$1"
  [[ -s "$file" ]] || return 1
  rg -q $'(^\\.youtube\\.com\\t|^youtube\\.com\\t|^\\.google\\.com\\t|^google\\.com\\t).*\\t(SID|SAPISID|LOGIN_INFO|__Secure-1PSID|__Secure-3PSID|VISITOR_INFO1_LIVE)\\t' "$file"
}

check_cookie_file() {
  local file="$1"
  if have_youtube_login_cookies "$file"; then
    log "OK: valid YouTube cookies found in $file"
    return 0
  fi
  log "FAIL: YouTube login cookies not found in $file"
  return 1
}

looks_repo_backed() {
  local target="$1"
  local resolved
  resolved="$(realpath -m "$target" 2>/dev/null || printf '%s' "$target")"
  [[ "$resolved" == "$HOME/.config/arch-config/"* || "$resolved" == "$HOME/.cachy/"* ]]
}

has_browser_root() {
  local root="$1"
  [[ -f "$root/Local State" ]] || return 1
  find "$root" -maxdepth 3 \( -path '*/Cookies' -o -path '*/Network/Cookies' \) -print -quit 2>/dev/null | grep -q .
}

try_export() {
  local browser="$1"
  local keyring="$2"
  local root="$3"
  local tmp="$4"

  rm -f "$tmp"
  log "Trying ${browser}+${keyring}:$root"
  timeout "$TRY_EXPORT_TIMEOUT" \
    "$YTDLP_BIN" \
      --ignore-config \
      --cookies-from-browser "${browser}+${keyring}:${root}" \
      --cookies "$tmp" \
      --skip-download \
      --playlist-end 1 \
      "$test_url" >/dev/null 2>&1 || true

  have_youtube_login_cookies "$tmp"
}

find_browser_source() {
  local candidate browser root keyring

  for candidate in "${CANDIDATES[@]}"; do
    browser="${candidate%%:*}"
    root="${candidate#*:}"
    [[ -d "$root" ]] || continue
    has_browser_root "$root" || continue

    for keyring in "${KEYRINGS[@]}"; do
      if try_export "$browser" "$keyring" "$root" "$tmp_cookie"; then
        printf '%s\n' "${browser}+${keyring}:${root}"
        return 0
      fi
    done
  done

  return 1
}

find_browser_sources() {
  local candidate browser root keyring

  for candidate in "${CANDIDATES[@]}"; do
    browser="${candidate%%:*}"
    root="${candidate#*:}"
    [[ -d "$root" ]] || continue
    has_browser_root "$root" || continue

    for keyring in "${KEYRINGS[@]}"; do
      if try_export "$browser" "$keyring" "$root" "$tmp_cookie"; then
        printf '%s\n' "${browser}+${keyring}:${root}"
        break
      fi
    done
  done
}

declare -a CANDIDATES=(
  "chromium:$HOME/.helium/isolated/helium-youtube.com__-Default"
  "chromium:$HOME/.helium/isolated/Kenp"
  "chromium:$HOME/.config/net.imput.helium"
  "brave:$HOME/.brave/isolated/Kenp"
  "brave:$HOME/.config/BraveSoftware/Brave-Browser"
)

declare -a KEYRINGS=(
  kwallet6
  gnomekeyring
  kwallet5
  kwallet
  basictext
)

if [[ "$mode" == "check" ]]; then
  check_cookie_file "$output_file"
  exit $?
fi

command -v "$YTDLP_BIN" >/dev/null 2>&1 || die "yt-dlp not found"
command -v rg >/dev/null 2>&1 || die "rg not found"

if [[ "$mode" != "source" && "$mode" != "sources" && -f "$output_file" ]] && ! $force; then
  if check_cookie_file "$output_file"; then
    log "Keeping existing cookies file. Use --force to refresh."
    exit 0
  fi
fi

if looks_repo_backed "$output_file"; then
  log "WARNING: $output_file resolves into a repo-backed path."
  log "WARNING: exporting cookies there can dirty your repo. Safer example:"
  log "WARNING:   yt-cookies-youtube --output ~/.local/state/yt-dlp/cookies-youtube.txt"
fi

tmp_cookie="$(mktemp /tmp/yt-cookies-youtube.XXXXXX.txt)"
trap 'rm -f "$tmp_cookie"' EXIT

selected=""
selected="$(find_browser_source || true)"

[[ -n "$selected" ]] || die "could not extract valid YouTube cookies from Helium/Brave profiles"

if [[ "$mode" == "source" ]]; then
  printf '%s\n' "$selected"
  exit 0
fi

if [[ "$mode" == "sources" ]]; then
  printf '%s\n' "$selected"
  find_browser_sources | awk '!seen[$0]++ && $0 != first' first="$selected"
  exit 0
fi

mkdir -p "$(dirname "$output_file")"
chmod 700 "$(dirname "$output_file")" 2>/dev/null || true

if [[ -f "$output_file" ]]; then
  backup="${output_file}.bak.$(date +%Y%m%d_%H%M%S)"
  cp -f "$output_file" "$backup"
  log "Backup written to $backup"
fi

mv -f "$tmp_cookie" "$output_file"
chmod 600 "$output_file" 2>/dev/null || true

log "YouTube cookies exported with $selected"
log "Saved to $output_file"
