#!/usr/bin/env bash
# ==============================================================================
# Script: mango-profile-select
# Description: Select the best MangoWM monitor profile from connected outputs.
# Usage: mango-profile-select [--write]
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
if [[ -n "${MANGO_REPO_ROOT:-}" ]]; then
  REPO_ROOT="$MANGO_REPO_ROOT"
elif [[ -r "$HOME/.cachy/shared/wm/monitors.yaml" ]]; then
  REPO_ROOT="$HOME/.cachy"
else
  REPO_ROOT="$(cd -- "${SCRIPT_DIR}/../../.." && pwd)"
fi
MONITORS_FILE="${MANGO_SHARED_MONITOR_MANIFEST:-${REPO_ROOT}/shared/wm/monitors.yaml}"
PROFILE_FILE="${MANGO_PROFILE_MANIFEST:-${REPO_ROOT}/modules/mangowm/profiles/profile.env}"
WRITE=0

usage() {
  cat <<'EOF'
Usage: mango-profile-select [--write]

Prints the best profile for currently connected Mango outputs. With --write,
updates modules/mangowm/profiles/profile.env to the selected concrete profile.
EOF
}

while (($#)); do
  case "$1" in
  --write)
    WRITE=1
    shift
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

[[ -r "$MONITORS_FILE" ]] || {
  echo "monitors manifest not found: $MONITORS_FILE" >&2
  exit 1
}

connected_outputs="$(
  if command -v mmsg >/dev/null 2>&1; then
    mmsg -O 2>/dev/null || true
  fi
)"

if [[ -z "$connected_outputs" ]] && command -v wlr-randr >/dev/null 2>&1; then
  connected_outputs="$(wlr-randr 2>/dev/null | awk '/^[^[:space:]]/ { print $1 }' || true)"
fi

selected="$(
  python3 - "$MONITORS_FILE" "$connected_outputs" <<'PY'
import sys
from pathlib import Path

import yaml

manifest = yaml.safe_load(Path(sys.argv[1]).read_text())
connected = {line.strip() for line in sys.argv[2].splitlines() if line.strip()}
monitors = {monitor["id"]: monitor for monitor in manifest.get("monitors", [])}
profiles = manifest.get("profiles", {})


def monitor_name(monitor):
    return monitor.get("mango_name", monitor.get("wayland_name", monitor["id"]))


def output_names(profile):
    names = []
    for output in profile.get("outputs", []):
        monitor_id = output.get("monitor")
        if not monitor_id:
            continue
        monitor = monitors.get(monitor_id)
        if monitor:
            names.append(monitor_name(monitor))
    return set(names)


if not connected:
    print("desk" if "desk" in profiles else next(iter(profiles), ""))
    raise SystemExit(0)

scored = []
for name, profile in profiles.items():
    names = output_names(profile)
    if not names:
        continue
    matched = len(names & connected)
    missing = len(names - connected)
    extra = len(connected - names)
    exact_subset = 1 if names <= connected else 0
    scored.append((exact_subset, matched, -missing, -extra, name))

if not scored:
    print("desk" if "desk" in profiles else next(iter(profiles), ""))
else:
    scored.sort(reverse=True)
    print(scored[0][-1])
PY
)"

[[ -n "$selected" ]] || {
  echo "unable to select a Mango profile" >&2
  exit 1
}

if [[ "$WRITE" -eq 1 ]]; then
  tmp="$(mktemp)"
  awk -v selected="$selected" '
    /^MANGO_MONITOR_PROFILE=/ {
      print "MANGO_MONITOR_PROFILE=" selected
      done = 1
      next
    }
    { print }
    END {
      if (!done) {
        print "MANGO_MONITOR_PROFILE=" selected
      }
    }
  ' "$PROFILE_FILE" >"$tmp"
  install -m 644 "$tmp" "$PROFILE_FILE"
  rm -f "$tmp"
fi

printf '%s\n' "$selected"
