#!/usr/bin/env bash
# ==============================================================================
# Script: wm-workspace.sh
# Description: Compositor-aware workspace router for Fusuma and helper scripts.
# ==============================================================================

set -euo pipefail

resolve_bin() {
  local name="$1"
  shift || true

  local candidates=("$@")
  local c
  for c in "${candidates[@]}"; do
    [[ -n "${c:-}" && -x "${c}" ]] && { printf '%s\n' "${c}"; return 0; }
  done

  command -v "${name}" 2>/dev/null || true
}

# systemd --user services often run with a minimal PATH; prefer common user bins.
NIRI_OSC="$(
  resolve_bin niri-osc \
    "${WM_WORKSPACE_NIRI_OSC:-}" \
    "${HOME}/.local/bin/niri-osc" \
    "${HOME}/bin/niri-osc"
)"

HYPR_OSC="$(
  resolve_bin hypr-osc \
    "${WM_WORKSPACE_HYPR_OSC:-${WM_WORKSPACE_HYPR_SET:-}}" \
    "${HOME}/.local/bin/hypr-osc" \
    "${HOME}/bin/hypr-osc"
)"

if [[ -n "${NIRI_SOCKET:-}" ]] || [[ "${XDG_CURRENT_DESKTOP:-}" == "niri" ]] || [[ "${XDG_SESSION_DESKTOP:-}" == "niri" ]]; then
  if [[ -n "${NIRI_OSC:-}" ]]; then
    exec "${NIRI_OSC}" set flow "$@"
  else
    echo "niri-osc not found in PATH" >&2
    exit 1
  fi
else
  if [[ -n "${HYPR_OSC:-}" ]]; then
    exec "${HYPR_OSC}" workspace-monitor "$@"
  else
    echo "hypr-osc not found in PATH" >&2
    exit 1
  fi
fi
