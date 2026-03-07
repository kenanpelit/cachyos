#!/usr/bin/env bash
# ==============================================================================
# Script: cleanup_helium_profiles.sh
# Description: Cleanup utility for Helium isolated profile disk usage.
# Usage: cleanup_helium_profiles.sh [options]
# ==============================================================================

set -euo pipefail

HELIUM_HOME="${HELIUM_HOME:-$HOME/.helium}"
HELIUM_HOME_INPUT=""
AGGRESSIVE=0
FORCE_CLOSE=0
ASSUME_YES=0

usage() {
  cat <<'EOF'
Usage: cleanup_helium_profiles.sh [options]

Options:
  --helium-home <path>  Target Helium home dir (default: $HELIUM_HOME or $HOME/.helium).
  --aggressive          Also remove "Service Worker" folders (more invasive).
  --force-close         Close matching Helium isolated-profile processes automatically.
  --yes                 Run without confirmation prompt.
  -h, --help            Show this help.

Examples:
  cleanup_helium_profiles.sh --yes --force-close
  cleanup_helium_profiles.sh --helium-home "$HOME/.helium" --aggressive --yes --force-close
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

find_running_pids() {
  local isolated_dir="$1"
  local isolated_dir_input="${2:-}"
  ps -eo pid=,args= | awk -v dir="$isolated_dir" -v dir_input="$isolated_dir_input" '
    {
      pid = $1
      $1 = ""
      sub(/^[[:space:]]+/, "", $0)
      cmd = $0

      if (cmd !~ /(^|[[:space:]])([^[:space:]]*\/)?(helium-browser|helium-wrapper|helium)([[:space:]]|$)/) {
        next
      }

      matches_dir = index(cmd, "--user-data-dir=" dir) || index(cmd, "--user-data-dir " dir)
      if (!matches_dir && dir_input != "") {
        matches_dir = index(cmd, "--user-data-dir=" dir_input) || index(cmd, "--user-data-dir " dir_input)
      }
      if (matches_dir) {
        print pid
      }
    }
  '
}

dir_bytes() {
  local target="$1"

  # HELIUM_HOME is resolved to a real path earlier, so we do not need -L here.
  # Avoids noisy errors from broken in-tree singleton symlinks.
  if du -sb -- "$target" >/dev/null 2>&1; then
    du -sb -- "$target" 2>/dev/null | awk '{print $1}'
  else
    # Fallback for systems where -b is unavailable.
    du -sk -- "$target" 2>/dev/null | awk '{print $1 * 1024}'
  fi
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --helium-home)
      [[ $# -lt 2 ]] && { echo "Missing value for --helium-home" >&2; exit 1; }
      HELIUM_HOME="$2"
      shift
      ;;
    --helium-home=*)
      HELIUM_HOME="${1#*=}"
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

HELIUM_HOME_INPUT="$HELIUM_HOME"
if [[ -L "$HELIUM_HOME" ]]; then
  resolved="$(readlink -f "$HELIUM_HOME" 2>/dev/null || true)"
  if [[ -n "$resolved" ]]; then
    HELIUM_HOME="$resolved"
  fi
fi

ISOLATED_DIR="$HELIUM_HOME/isolated"
ISOLATED_DIR_INPUT="$HELIUM_HOME_INPUT/isolated"

if [[ ! -d "$ISOLATED_DIR" ]]; then
  echo "isolated directory not found: $ISOLATED_DIR" >&2
  exit 1
fi

RUNNING_PIDS="$(find_running_pids "$ISOLATED_DIR" "$ISOLATED_DIR_INPUT" || true)"
if [[ -n "$RUNNING_PIDS" ]]; then
  if [[ "$FORCE_CLOSE" -eq 1 ]]; then
    printf '%s\n' "$RUNNING_PIDS" | xargs -r kill -TERM
    sleep 2
    REMAINING="$(find_running_pids "$ISOLATED_DIR" "$ISOLATED_DIR_INPUT" || true)"
    if [[ -n "$REMAINING" ]]; then
      printf '%s\n' "$REMAINING" | xargs -r kill -KILL
    fi
  else
    echo "Helium isolated profiles are running. Close them first or use --force-close." >&2
    exit 1
  fi
fi

if [[ "$ASSUME_YES" -ne 1 ]]; then
  echo "Target Helium home: $HELIUM_HOME"
  echo "Will remove:"
  echo "- *.bak-* profile folders under: $ISOLATED_DIR"
  echo "- Cache folders: Cache, Code Cache, GPUCache, GrShaderCache, ShaderCache,"
  echo "  DawnGraphiteCache, DawnWebGPUCache, GraphiteDawnCache,"
  echo "  component_crx_cache, extensions_crx_cache"
  if [[ "$AGGRESSIVE" -eq 1 ]]; then
    echo "- Service Worker folders (aggressive mode)"
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

BEFORE_BYTES="$(dir_bytes "$HELIUM_HOME")"

# Remove backup profile snapshots.
find "$ISOLATED_DIR" -maxdepth 2 -mindepth 2 -type d -name '*.bak-*' -exec rm -rf {} +

# Remove safe cache directories.
find "$ISOLATED_DIR" -type d \
  \( -name 'Cache' -o -name 'Code Cache' -o -name 'GPUCache' -o -name 'GrShaderCache' \
     -o -name 'ShaderCache' -o -name 'DawnGraphiteCache' -o -name 'DawnWebGPUCache' \
     -o -name 'GraphiteDawnCache' -o -name 'component_crx_cache' \
     -o -name 'extensions_crx_cache' \) \
  -exec rm -rf {} +

if [[ "$AGGRESSIVE" -eq 1 ]]; then
  find "$ISOLATED_DIR" -type d -name 'Service Worker' -exec rm -rf {} +
fi

AFTER_BYTES="$(dir_bytes "$HELIUM_HOME")"
FREED_BYTES=$((BEFORE_BYTES - AFTER_BYTES))
if [[ "$FREED_BYTES" -lt 0 ]]; then
  FREED_BYTES=0
fi

echo "Target: $HELIUM_HOME"
if [[ "$HELIUM_HOME_INPUT" != "$HELIUM_HOME" ]]; then
  echo "Resolved from: $HELIUM_HOME_INPUT"
fi
echo "Before: $(to_human "$BEFORE_BYTES")"
echo "After:  $(to_human "$AFTER_BYTES")"
echo "Freed:  $(to_human "$FREED_BYTES")"
