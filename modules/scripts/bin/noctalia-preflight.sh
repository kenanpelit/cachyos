#!/usr/bin/env bash
# ==============================================================================
# Script: noctalia-preflight.sh
# Description: Ensure writable Noctalia runtime files exist before launch.
# ==============================================================================
set -euo pipefail

config_home="${XDG_CONFIG_HOME:-$HOME/.config}"
settings_file="${config_home}/noctalia/settings.json"
clipper_dir="${config_home}/noctalia/plugins/clipper"
pinned_file="${clipper_dir}/pinned.json"

for ((i = 0; i < 20; i++)); do
  [[ -f "${settings_file}" ]] && break
  sleep 0.1
done

mkdir -p "${clipper_dir}/notecards"

if [[ ! -f "${pinned_file}" ]]; then
  printf '%s\n' '{"items":[]}' > "${pinned_file}"
fi
