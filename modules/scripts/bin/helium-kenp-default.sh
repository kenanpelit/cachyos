#!/usr/bin/env bash
# ==============================================================================
# Script: helium-kenp-default.sh
# Description: Default browser entry for Kenp profile with niri window focus.
# Usage: helium-kenp-default.sh [URL]
# ==============================================================================

set -euo pipefail

resolve_profile_helium() {
  local script_dir candidate
  script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

  for candidate in \
    "${script_dir}/profile_helium" \
    "${HOME}/.local/bin/profile_helium" \
    "/usr/local/bin/profile_helium" \
    "profile_helium"; do
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

if profile_helium_cmd="$(resolve_profile_helium 2>/dev/null)"; then
  if [[ $# -gt 0 ]]; then
    # Keep Kenp app-id/class by targeting the isolated Kenp instance.
    "${profile_helium_cmd}" Kenp --separate --new-tab "$@"
  else
    "${profile_helium_cmd}" Kenp --separate
  fi
  focus_kenp_window_niri
  exit 0
fi

if command -v helium-browser >/dev/null 2>&1; then
  exec helium-browser --profile-directory=Default "$@"
fi

if [[ -x /opt/helium-browser-bin/helium-wrapper ]]; then
  exec /opt/helium-browser-bin/helium-wrapper --profile-directory=Default "$@"
fi

echo "helium-kenp-default: helium not found" >&2
exit 127
