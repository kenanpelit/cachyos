#!/usr/bin/env bash
# ==============================================================================
# Script: cleanup_zen_profiles.sh
# Description: Cleanup utility for Zen (Firefox-based) profile disk usage.
# Usage: cleanup_zen_profiles.sh [options]
#
# Unlike the Chromium cousins (cleanup_helium_profiles.sh / cleanup_brave_profiles.sh)
# Zen is Firefox-based, so the layout differs:
#   - Profiles live directly under $ZEN_HOME/<profile> (no "isolated/" dir,
#     no --user-data-dir, no *.bak-* snapshots).
#   - The bulky disk cache lives OUTSIDE the profile, under
#     $XDG_CACHE_HOME/zen/<profile> (cache2 alone is usually hundreds of MB).
#   - Running profiles are detected via the Firefox "lock" symlink
#     (lock -> <addr>:+<pid>), not by scanning --user-data-dir in argv.
#
# Only regenerable caches are removed. Site data, logins, cookies, bookmarks,
# Sync (weave), extensions and session backups are left untouched.
# ==============================================================================

set -euo pipefail

ZEN_HOME="${ZEN_HOME:-$HOME/.zen}"
ZEN_CACHE_HOME="${ZEN_CACHE_HOME:-${XDG_CACHE_HOME:-$HOME/.cache}/zen}"
ZEN_HOME_INPUT=""
ZEN_CACHE_HOME_INPUT=""
PROFILE_FILTER=""
AGGRESSIVE=0
FORCE_CLOSE=0
ASSUME_YES=0

usage() {
  cat <<'EOF'
Usage: cleanup_zen_profiles.sh [options]

Options:
  --zen-home <path>     Target Zen home dir (default: $ZEN_HOME or $HOME/.zen).
  --cache-home <path>   Target Zen cache dir (default: $ZEN_CACHE_HOME or
                        $XDG_CACHE_HOME/zen, i.e. ~/.cache/zen).
  --profile <name>      Only clean this profile (by profiles.ini Path/dir name).
                        May be repeated. Default: every profile.
  --aggressive          Also wipe the whole per-profile cache dir and
                        sessionstore-backups (more invasive, loses "restore
                        previous session" recovery points).
  --force-close         Close matching running Zen profiles automatically.
  --yes                 Run without confirmation prompt.
  -h, --help            Show this help.

Examples:
  cleanup_zen_profiles.sh --yes --force-close
  cleanup_zen_profiles.sh --profile kenp --aggressive --yes --force-close
EOF
}

to_human() {
  local bytes="$1"
  if command -v numfmt >/dev/null 2>&1; then
    numfmt --to=iec-i --suffix=B "$bytes"
  else
    echo "${bytes}B"
  fi
}

dir_bytes() {
  local target="$1"

  [[ -e "$target" ]] || { echo 0; return 0; }

  # Paths are resolved to real paths earlier, so we do not need -L here.
  # Avoids noisy errors from broken in-tree singleton symlinks (lock, etc.).
  if du -sb -- "$target" >/dev/null 2>&1; then
    du -sb -- "$target" 2>/dev/null | awk '{print $1}'
  else
    # Fallback for systems where -b is unavailable.
    du -sk -- "$target" 2>/dev/null | awk '{print $1 * 1024}'
  fi
}

resolve_path() {
  # Resolve a symlinked dir to its real path, echo input unchanged otherwise.
  local p="$1"
  if [[ -L "$p" ]]; then
    local r
    r="$(readlink -f "$p" 2>/dev/null || true)"
    [[ -n "$r" ]] && { printf '%s\n' "$r"; return 0; }
  fi
  printf '%s\n' "$p"
}

# List profile directory names. Prefer profiles.ini Path= entries (authoritative);
# fall back to subdirs that look like real profiles (have times.json / prefs.js).
list_profiles() {
  local ini="$ZEN_HOME/profiles.ini"
  if [[ -f "$ini" ]]; then
    awk -F= '
      /^\[Profile/  { inprof=1; next }
      /^\[/         { inprof=0 }
      inprof && $1=="Path" { sub(/\r$/, "", $2); print $2 }
    ' "$ini"
    return 0
  fi

  local d
  for d in "$ZEN_HOME"/*/; do
    [[ -f "${d}times.json" || -f "${d}prefs.js" ]] && basename "$d"
  done
}

# Echo the live PID holding a profile's lock, or nothing. Firefox writes the
# lock as a symlink "lock -> <addr>:+<pid>"; .parentlock carries no pid.
profile_lock_pid() {
  local prof_dir="$1"
  local link target pid
  link="$prof_dir/lock"
  [[ -L "$link" ]] || return 0
  target="$(readlink "$link" 2>/dev/null || true)"
  pid="${target##*+}"
  [[ "$pid" =~ ^[0-9]+$ ]] || return 0
  if kill -0 "$pid" 2>/dev/null; then
    printf '%s\n' "$pid"
  fi
  return 0
}

PROFILE_FILTERS=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --zen-home)
      [[ $# -lt 2 ]] && { echo "Missing value for --zen-home" >&2; exit 1; }
      ZEN_HOME="$2"
      shift
      ;;
    --zen-home=*)
      ZEN_HOME="${1#*=}"
      ;;
    --cache-home)
      [[ $# -lt 2 ]] && { echo "Missing value for --cache-home" >&2; exit 1; }
      ZEN_CACHE_HOME="$2"
      shift
      ;;
    --cache-home=*)
      ZEN_CACHE_HOME="${1#*=}"
      ;;
    --profile)
      [[ $# -lt 2 ]] && { echo "Missing value for --profile" >&2; exit 1; }
      PROFILE_FILTERS+=("$2")
      shift
      ;;
    --profile=*)
      PROFILE_FILTERS+=("${1#*=}")
      ;;
    --aggressive)
      AGGRESSIVE=1
      ;;
    --force-close)
      FORCE_CLOSE=1
      ;;
    --yes)
      ASSUME_YES=1
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage
      exit 1
      ;;
  esac
  shift
done

ZEN_HOME_INPUT="$ZEN_HOME"
ZEN_CACHE_HOME_INPUT="$ZEN_CACHE_HOME"
ZEN_HOME="$(resolve_path "$ZEN_HOME")"
ZEN_CACHE_HOME="$(resolve_path "$ZEN_CACHE_HOME")"

if [[ ! -d "$ZEN_HOME" ]]; then
  echo "Zen home not found: $ZEN_HOME" >&2
  exit 1
fi

# Build the working profile list, applying --profile filters if any.
mapfile -t ALL_PROFILES < <(list_profiles | awk 'NF' | sort -u)
PROFILES=()
if [[ ${#PROFILE_FILTERS[@]} -gt 0 ]]; then
  for want in "${PROFILE_FILTERS[@]}"; do
    found=0
    for have in "${ALL_PROFILES[@]}"; do
      [[ "$have" == "$want" ]] && { PROFILES+=("$want"); found=1; break; }
    done
    [[ "$found" -eq 0 ]] && echo "Warning: profile not found, skipping: $want" >&2
  done
else
  PROFILES=("${ALL_PROFILES[@]}")
fi

if [[ ${#PROFILES[@]} -eq 0 ]]; then
  echo "No Zen profiles to clean under: $ZEN_HOME" >&2
  exit 1
fi

# Detect running profiles via their lock symlinks.
RUNNING_PIDS=()
RUNNING_NAMES=()
for prof in "${PROFILES[@]}"; do
  pid="$(profile_lock_pid "$ZEN_HOME/$prof" || true)"
  if [[ -n "$pid" ]]; then
    RUNNING_PIDS+=("$pid")
    RUNNING_NAMES+=("$prof")
  fi
done

if [[ ${#RUNNING_PIDS[@]} -gt 0 ]]; then
  if [[ "$FORCE_CLOSE" -eq 1 ]]; then
    printf '%s\n' "${RUNNING_PIDS[@]}" | xargs -r kill -TERM
    sleep 2
    # Re-check and hard-kill stragglers.
    STILL=()
    for prof in "${RUNNING_NAMES[@]}"; do
      pid="$(profile_lock_pid "$ZEN_HOME/$prof" || true)"
      [[ -n "$pid" ]] && STILL+=("$pid")
    done
    if [[ ${#STILL[@]} -gt 0 ]]; then
      printf '%s\n' "${STILL[@]}" | xargs -r kill -KILL
    fi
  else
    echo "Zen profiles are running: ${RUNNING_NAMES[*]}" >&2
    echo "Close them first or use --force-close." >&2
    exit 1
  fi
fi

if [[ "$ASSUME_YES" -ne 1 ]]; then
  echo "Target Zen home:  $ZEN_HOME"
  echo "Target Zen cache: $ZEN_CACHE_HOME"
  echo "Profiles:         ${PROFILES[*]}"
  echo "Will remove (regenerable caches only — site data/logins/bookmarks kept):"
  echo "- Cache dirs under \$cache-home/<profile>: cache2, startupCache,"
  echo "  OfflineCache, safebrowsing, thumbnails, shader-cache, jumpListCache"
  echo "- Profile dirs under \$zen-home/<profile>: startupCache, shader-cache,"
  echo "  OfflineCache, crashes, minidumps, datareporting, saved-telemetry-pings,"
  echo "  storage/temporary, storage/to-be-removed"
  if [[ "$AGGRESSIVE" -eq 1 ]]; then
    echo "- AGGRESSIVE: entire \$cache-home/<profile> contents + sessionstore-backups"
  fi
  read -r -p "Continue? [y/N] " answer
  case "$answer" in
    y|Y|yes|YES)
      ;;
    *)
      echo "Cancelled."
      exit 0
      ;;
  esac
fi

BEFORE_BYTES=$(( $(dir_bytes "$ZEN_HOME") + $(dir_bytes "$ZEN_CACHE_HOME") ))

# Cache-root subdirs that are pure caches (default mode).
CACHE_SUBDIRS=(cache2 startupCache OfflineCache safebrowsing thumbnails shader-cache jumpListCache)
# Profile-root subdirs that are regenerable (default mode).
PROFILE_SUBDIRS=(startupCache shader-cache OfflineCache crashes minidumps datareporting saved-telemetry-pings)

for prof in "${PROFILES[@]}"; do
  cache_dir="$ZEN_CACHE_HOME/$prof"
  prof_dir="$ZEN_HOME/$prof"

  if [[ "$AGGRESSIVE" -eq 1 ]]; then
    # Wipe everything under the cache root for this profile.
    if [[ -d "$cache_dir" ]]; then
      find "$cache_dir" -mindepth 1 -maxdepth 1 -exec rm -rf {} +
    fi
    rm -rf -- "$prof_dir/sessionstore-backups"
  else
    for sub in "${CACHE_SUBDIRS[@]}"; do
      rm -rf -- "$cache_dir/$sub"
    done
  fi

  for sub in "${PROFILE_SUBDIRS[@]}"; do
    rm -rf -- "$prof_dir/$sub"
  done
  rm -rf -- "$prof_dir/storage/temporary" "$prof_dir/storage/to-be-removed"
done

AFTER_BYTES=$(( $(dir_bytes "$ZEN_HOME") + $(dir_bytes "$ZEN_CACHE_HOME") ))
FREED_BYTES=$((BEFORE_BYTES - AFTER_BYTES))
if [[ "$FREED_BYTES" -lt 0 ]]; then
  FREED_BYTES=0
fi

echo "Target: $ZEN_HOME (+ cache $ZEN_CACHE_HOME)"
if [[ "$ZEN_HOME_INPUT" != "$ZEN_HOME" ]]; then
  echo "Resolved from: $ZEN_HOME_INPUT"
fi
echo "Profiles cleaned: ${PROFILES[*]}"
echo "Before: $(to_human "$BEFORE_BYTES")"
echo "After:  $(to_human "$AFTER_BYTES")"
echo "Freed:  $(to_human "$FREED_BYTES")"
