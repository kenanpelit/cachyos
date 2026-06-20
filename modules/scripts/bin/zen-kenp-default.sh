#!/usr/bin/env bash
# ==============================================================================
# Script: zen-kenp-default.sh
# Description: Default browser entry for the Zen Kenp profile with niri focus.
#              Mirrors helium-kenp-default.sh for the Zen (Firefox-based) browser.
# Usage: zen-kenp-default.sh [URL]
# ==============================================================================

set -euo pipefail

resolve_zen() {
  local candidate
  for candidate in \
    zen-browser \
    /usr/bin/zen-browser \
    zen; do
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

if zen_cmd="$(resolve_zen 2>/dev/null)"; then
  if [[ $# -gt 0 ]]; then
    # Open the URL in a new tab of the existing Kenp window (keeps Kenp app-id/class).
    "${zen_cmd}" -P kenp --name Kenp --class Kenp --new-tab "$@"
  else
    "${zen_cmd}" -P kenp --name Kenp --class Kenp
  fi
  focus_kenp_window_niri
  exit 0
fi

echo "zen-kenp-default: zen not found" >&2
exit 127
