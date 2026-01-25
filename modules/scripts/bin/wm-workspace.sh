#!/usr/bin/env bash
# wm-workspace.sh
# Workspace router across compositors (Hyprland, Niri).
# Used by Fusuma (and other callers) to route workspace/monitor actions to the
# correct backend (`hypr-set`, `niri-set`).

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
NIRI_SET="$(
  resolve_bin niri-set \
    "${WM_WORKSPACE_NIRI_SET:-}" \
    "${HOME}/.local/bin/niri-set" \
    "${HOME}/bin/niri-set"
)"

HYPR_SET="$(
  resolve_bin hypr-set \
    "${WM_WORKSPACE_HYPR_SET:-}" \
    "${HOME}/.local/bin/hypr-set" \
    "${HOME}/bin/hypr-set"
)"

if [[ -n "${NIRI_SOCKET:-}" ]] || [[ "${XDG_CURRENT_DESKTOP:-}" == "niri" ]] || [[ "${XDG_SESSION_DESKTOP:-}" == "niri" ]]; then
  if [[ -n "${NIRI_SET:-}" ]]; then
    exec "${NIRI_SET}" flow "$@"
  else
    echo "niri-set not found in PATH" >&2
    exit 1
  fi
else
  if [[ -n "${HYPR_SET:-}" ]]; then
    exec "${HYPR_SET}" workspace-monitor "$@"
  else
    echo "hypr-set not found in PATH" >&2
    exit 1
  fi
fi
