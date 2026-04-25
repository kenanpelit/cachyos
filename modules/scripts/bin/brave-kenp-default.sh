#!/usr/bin/env bash
# ==============================================================================
# Script: brave-kenp-default.sh
# Description: Default browser entry for Kenp profile with niri window focus.
# Usage: brave-kenp-default.sh [URL]
# ==============================================================================

set -euo pipefail

resolve_brave_binary() {
  local requested="${BRAVE_BIN:-}"
  local preference="${BRAVE_VARIANT_PREFERENCE:-origin}"
  local candidate
  local -a candidates=()

  append_candidate() {
    local value="$1"
    local existing
    [[ -n "$value" ]] || return 0
    for existing in "${candidates[@]}"; do
      [[ "$existing" == "$value" ]] && return 0
    done
    candidates+=("$value")
  }

  case "${requested:-}" in
    ""|auto|brave|brave-browser|brave-bin)
      ;;
    *)
      append_candidate "$requested"
      ;;
  esac

  if [[ "$preference" == "browser" ]]; then
    append_candidate "brave"
    append_candidate "brave-browser"
    append_candidate "brave-origin"
    append_candidate "brave-origin-beta"
  else
    append_candidate "brave-origin"
    append_candidate "brave-origin-beta"
    append_candidate "brave"
    append_candidate "brave-browser"
  fi

  for candidate in "${candidates[@]}"; do
    if command -v "${candidate}" >/dev/null 2>&1; then
      command -v "${candidate}"
      return 0
    fi
  done

  return 1
}

resolve_profile_brave() {
  local script_dir candidate
  script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

  for candidate in \
    "${script_dir}/profile_brave" \
    "${HOME}/.local/bin/profile_brave" \
    "/usr/local/bin/profile_brave" \
    "profile_brave"; do
    if command -v "${candidate}" >/dev/null 2>&1; then
      command -v "${candidate}"
      return 0
    fi
  done

  return 1
}

focus_kenp_window_niri() {
  command -v niri >/dev/null 2>&1 || return 0

  local tries=8
  local delay="0.12"
  local window_id=""

  while ((tries > 0)); do
    if command -v niri-osc >/dev/null 2>&1; then
      if niri-osc flow focus --app-id '^Kenp$' >/dev/null 2>&1; then
        return 0
      fi
    fi

    if command -v jq >/dev/null 2>&1; then
      window_id="$(
        niri msg -j windows 2>/dev/null \
          | jq -r 'first(.[] | select(((.app_id // "") | tostring) == "Kenp") | .id) // empty' \
          || true
      )"
      if [[ -n "${window_id}" ]]; then
        niri msg action focus-window --id "${window_id}" >/dev/null 2>&1 || true
        return 0
      fi
    fi

    sleep "${delay}"
    ((tries--))
  done

  return 0
}

if profile_brave_cmd="$(resolve_profile_brave 2>/dev/null)"; then
  if [[ $# -gt 0 ]]; then
    # Keep Kenp app-id/class by targeting the isolated Kenp instance.
    "${profile_brave_cmd}" Kenp --separate --new-tab "$@"
  else
    "${profile_brave_cmd}" Kenp --separate
  fi
  focus_kenp_window_niri
  exit 0
fi

if brave_bin="$(resolve_brave_binary 2>/dev/null)"; then
  exec "${brave_bin}" --profile-directory=Default "$@"
fi

echo "brave-kenp-default: brave not found" >&2
exit 127
