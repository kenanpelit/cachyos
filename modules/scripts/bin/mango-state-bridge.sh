#!/usr/bin/env bash
# ==============================================================================
# Script: mango-state-bridge
# Description: Export MangoWM IPC state as JSON for shell integrations.
# Usage: mango-state-bridge [--once|--watch] [--output FILE]
# ==============================================================================

set -euo pipefail

MODE="once"
STATE_FILE="${MANGO_STATE_FILE:-${XDG_CACHE_HOME:-${HOME}/.cache}/mango/state.json}"
WATCH_INTERVAL="${MANGO_STATE_BRIDGE_INTERVAL:-5}"

usage() {
  cat <<'EOF'
Usage: mango-state-bridge [--once|--watch] [--output FILE]

Writes output, tag, layout, keymode, layer, and focused-client state from mmsg
to a JSON file that panels or Noctalia plugins can read without parsing IPC.
Watch mode refreshes periodically; tune it with MANGO_STATE_BRIDGE_INTERVAL.
EOF
}

while (($#)); do
  case "$1" in
  --once)
    MODE="once"
    shift
    ;;
  --watch)
    MODE="watch"
    shift
    ;;
  --output)
    STATE_FILE="$2"
    shift 2
    ;;
  -h | --help | help)
    usage
    exit 0
    ;;
  *)
    usage >&2
    exit 2
    ;;
  esac
done

command -v mmsg >/dev/null 2>&1 || {
  echo "mmsg is required" >&2
  exit 1
}
command -v python3 >/dev/null 2>&1 || {
  echo "python3 is required" >&2
  exit 1
}

write_state() {
  local output_dir tmp
  output_dir="$(dirname -- "$STATE_FILE")"
  mkdir -p "$output_dir"
  tmp="$(mktemp "${output_dir}/.mango-state.XXXXXX")"

  python3 - "$tmp" <<'PY'
import json
import subprocess
import sys
import time
from pathlib import Path

target = Path(sys.argv[1])


def mmsg(*args):
    try:
        return subprocess.check_output(["mmsg", *args], text=True, stderr=subprocess.DEVNULL)
    except Exception:
        return ""


def parse_monitor_lines(raw, marker):
    result = {}
    for line in raw.splitlines():
        parts = line.split(maxsplit=2)
        if len(parts) == 3 and parts[1] == marker:
            result[parts[0]] = parts[2]
    return result


state = {
    "updatedAt": int(time.time()),
    "outputs": [line.strip() for line in mmsg("-O").splitlines() if line.strip()],
    "layouts": parse_monitor_lines(mmsg("-g", "-l"), "layout"),
    "keymodes": parse_monitor_lines(mmsg("-g", "-b"), "keymode"),
    "layers": {},
    "clients": {},
    "tags": {},
}

for line in mmsg("-g", "-e").splitlines():
    parts = line.split(maxsplit=2)
    if len(parts) == 3 and parts[1] == "last_layer":
        state["layers"][parts[0]] = parts[2]

current = None
for line in mmsg("-g", "-c").splitlines():
    parts = line.split(maxsplit=2)
    if len(parts) != 3:
        continue
    monitor, key, value = parts
    current = state["clients"].setdefault(monitor, {})
    current[key] = value

for line in mmsg("-g", "-t").splitlines():
    parts = line.split()
    if len(parts) == 5 and parts[1] == "tags" and parts[2].isdigit():
        state["tags"][parts[0]] = {
            "occupiedMask": int(parts[2]),
            "activeMask": int(parts[3]),
            "urgentMask": int(parts[4]),
        }

target.write_text(json.dumps(state, indent=2, sort_keys=True) + "\n")
PY

  mv -f "$tmp" "$STATE_FILE"
}

write_state

if [[ "$MODE" == "watch" ]]; then
  while :; do
    sleep "$WATCH_INTERVAL"
    write_state
  done
fi
