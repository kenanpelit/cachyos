#!/usr/bin/env bash
set -euo pipefail

# Default browser entry for Kenp profile.
# Use shared Brave instance so links open as tabs in the existing window.

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
    # For URL handlers keep a shared instance so links reuse the existing Kenp window/tab.
    "${profile_brave_cmd}" Kenp --no-separate --new-tab "$@"
  else
    "${profile_brave_cmd}" Kenp --no-separate
  fi
  focus_kenp_window_niri
  exit 0
fi

if command -v brave >/dev/null 2>&1; then
  exec brave --profile-directory=Default "$@"
fi

if command -v brave-browser >/dev/null 2>&1; then
  exec brave-browser --profile-directory=Default "$@"
fi

echo "brave-kenp-default: brave not found" >&2
exit 127
