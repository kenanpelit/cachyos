#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: mango-here <tag> <monitor> <target>

Focus the target tag on the target monitor, then launch its mapped app only if
that tag is empty.
EOF
}

[[ $# -eq 3 ]] || {
  usage >&2
  exit 2
}

tag="$1"
monitor="$2"
target="$3"

[[ "${tag}" =~ ^[1-9]$ ]] || {
  echo "tag must be between 1 and 9" >&2
  exit 2
}

command -v mmsg >/dev/null 2>&1 || {
  echo "mmsg is required" >&2
  exit 1
}

launch_cmd=""
if command -v osc-workspace-launch >/dev/null 2>&1; then
  launch_cmd="$(osc-workspace-launch first-existing "${target}" 2>/dev/null || true)"
fi

if [[ -z "${launch_cmd}" ]]; then
  case "${target}" in
    discord)
      launch_cmd="start-discord"
      ;;
  esac
fi

mmsg -d "viewcrossmon,${tag},${monitor}"

if [[ -n "${launch_cmd}" ]]; then
  exec mmsg -d "spawn_on_empty,${launch_cmd},${tag}"
fi

exit 0
