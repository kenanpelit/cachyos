#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: mango-workspace-smart <tag> <monitor>

Focus the target monitor, then switch to the requested tag using MangoWM's
native `view` command so `view_current_to_back=1` keeps working.
EOF
}

[[ $# -eq 2 ]] || {
  usage >&2
  exit 2
}

tag="$1"
monitor="$2"

[[ "${tag}" =~ ^[1-9]$ ]] || {
  echo "tag must be between 1 and 9" >&2
  exit 2
}

command -v mmsg >/dev/null 2>&1 || {
  echo "mmsg is required" >&2
  exit 1
}

current_monitor="$(
  mmsg -g -o 2>/dev/null | awk '$2 == "selmon" && $3 == "1" { print $1; exit }'
)"

if [[ -n "${monitor}" && "${current_monitor}" != "${monitor}" ]]; then
  mmsg -d "focusmon,${monitor}"
fi

exec mmsg -d "view,${tag},0"
