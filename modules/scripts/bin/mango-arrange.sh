#!/usr/bin/env bash
# ==============================================================================
# Script: mango-arrange
# Description: Profile-aware initial tag arrangement for MangoWM.
# Usage: mango-arrange
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMMON_HELPER="${SCRIPT_DIR}/mango-session-common.sh"
[[ -r "${COMMON_HELPER}" ]] || COMMON_HELPER="${SCRIPT_DIR}/mango-session-common"
# shellcheck source=mango-session-common.sh
source "${COMMON_HELPER}"

PROFILE_FILE="${MANGO_PROFILE_FILE:-${XDG_CONFIG_HOME:-$HOME/.config}/mango/runtime/profile.conf}"
LOG_TAG="mango-arrange"

log() { printf '[%s] %s\n' "${LOG_TAG}" "$*" >&2; }
warn() { printf '[%s] WARN: %s\n' "${LOG_TAG}" "$*" >&2; }

export PATH="$HOME/.local/bin:$HOME/bin:/usr/local/bin:/usr/bin:/bin:${PATH:-}"

main() {
  mango_ensure_runtime_dir
  mango_ensure_session_identity
  mango_detect_wayland_display || true

  if ! command -v mmsg >/dev/null 2>&1; then
    warn "mmsg not found; skipping arrangement"
    exit 0
  fi

  if [[ ! -r "${PROFILE_FILE}" ]]; then
    warn "profile file not found: ${PROFILE_FILE}"
    exit 0
  fi

  mapfile -t target_pairs < <(
    awk -F',' '
      /^tagrule=/ {
        tag=""
        monitor=""
        for (i = 1; i <= NF; i++) {
          if ($i ~ /^tagrule=id:/) {
            tag = $i
            sub(/^tagrule=id:/, "", tag)
          } else if ($i ~ /^monitor_name:/) {
            monitor = $i
            sub(/^monitor_name:/, "", monitor)
          }
        }
        if (tag != "" && monitor != "") {
          print monitor "\t" tag
        }
      }
    ' "${PROFILE_FILE}" | awk -F'\t' '!seen[$1]++'
  )

  if (( ${#target_pairs[@]} == 0 )); then
    warn "no tag mappings found in ${PROFILE_FILE}"
    exit 0
  fi

  if ! mmsg -g -o >/dev/null 2>&1; then
    warn "cannot query Mango outputs; skipping arrangement"
    exit 0
  fi

  first_monitor=""
  first_tag=""
  for pair in "${target_pairs[@]}"; do
    monitor="${pair%%$'\t'*}"
    tag="${pair#*$'\t'}"
    [[ -n "${monitor}" && -n "${tag}" ]] || continue
    if [[ -z "${first_monitor}" ]]; then
      first_monitor="${monitor}"
      first_tag="${tag}"
    fi
    mmsg -s -o "${monitor}" -t "${tag}" >/dev/null 2>&1 || true
  done

  if [[ -n "${first_monitor}" && -n "${first_tag}" ]]; then
    mmsg -d "focusmon,${first_monitor}" >/dev/null 2>&1 || true
    mmsg -s -o "${first_monitor}" -t "${first_tag}" >/dev/null 2>&1 || true
    log "focused ${first_monitor} on tag ${first_tag}"
  fi
}

main "$@"
