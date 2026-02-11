#!/usr/bin/env bash
set -euo pipefail

# Backward-compatible wrapper: old `niri-flow` now lives under `niri-osc flow`.
osc_bin="$(command -v niri-osc 2>/dev/null || true)"
if [[ -z "${osc_bin}" && -x "${HOME}/.local/bin/niri-osc" ]]; then
  osc_bin="${HOME}/.local/bin/niri-osc"
fi
if [[ -z "${osc_bin}" && -x "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/niri-osc.sh" ]]; then
  osc_bin="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/niri-osc.sh"
fi
if [[ -z "${osc_bin}" ]]; then
  echo "niri-flow: niri-osc not found in PATH" >&2
  exit 127
fi
exec "${osc_bin}" flow "$@"
