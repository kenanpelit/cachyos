#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
MODULE_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/../../.." && pwd)"

source "$REPO_ROOT/modules/base/lib/core.sh"

bin_dir="$USER_HOME/.local/bin"
wrapper_src="$MODULE_ROOT/scripts/yt-dlp-mpv"
wrapper_dst="$bin_dir/yt-dlp-mpv"
legacy_root_dst="/root/.local/bin/yt-dlp-mpv"

run_as_user mkdir -p "$bin_dir"
run_as_user chmod 0755 "$bin_dir"
chmod +x "$wrapper_src" || true
run_as_user ln -sfn "$wrapper_src" "$wrapper_dst"

# Earlier versions wrote into /root/.local/bin when the hook ran under sudo.
if [[ "$(id -u)" -eq 0 && -L "$legacy_root_dst" ]]; then
  rm -f "$legacy_root_dst"
fi

log_success "yt-dlp-mpv installed to $wrapper_dst"
