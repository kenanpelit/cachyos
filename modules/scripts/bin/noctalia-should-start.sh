#!/usr/bin/env bash
set -euo pipefail

case "${XDG_CURRENT_DESKTOP:-}" in
  niri|Niri|Hyprland|hyprland)
    ;;
  *)
    exit 1
    ;;
esac

backend_cmd="$(command -v osc-shell 2>/dev/null || true)"
if [[ -z "${backend_cmd}" && -x "${HOME}/.local/bin/osc-shell" ]]; then
  backend_cmd="${HOME}/.local/bin/osc-shell"
fi

backend="noctalia"
if [[ -n "${backend_cmd}" ]]; then
  backend="$("${backend_cmd}" backend 2>/dev/null || printf '%s\n' "noctalia")"
fi

[[ "${backend}" == "noctalia" ]]
