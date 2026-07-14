#!/usr/bin/env bash

# tagwarp
# Switch Margo to a target tag reliably during startup or manual use.
#
# Usage: tagwarp [TAG] [OUTPUT]
#
# OUTPUT defaults to DP-3 (tags 1-6 per the margo tagrules; use eDP-1 for
# 7-9), overridable via $TAGWARP_OUTPUT or arg 2. Pinning the output matters:
# `mctl tags` without `-o` targets margo's *active* output, and during
# startup a late-mapping app (Electron cold start on the other monitor) can
# steal focus right before we run — the switch then lands on the wrong
# monitor and the session appears to "ignore" tagwarp.

set -u

TAG="${1:-2}"
OUTPUT="${2:-${TAGWARP_OUTPUT:-DP-3}}"
# mctl takes a raw bitmask, not a tag number (tag N = 1 << (N-1)).
MASK=$((1 << (TAG - 1)))
APP_NAME="MARGO"
ICON_NAME="view-grid-symbolic"
LOG_FILE="${XDG_CACHE_HOME:-$HOME/.cache}/tagwarp.log"

mkdir -p "$(dirname "$LOG_FILE")"

log() {
  printf '[%s] %s\n' "$(date '+%F %T')" "$*" >>"$LOG_FILE"
}

notify() {
  if command -v mshellctl >/dev/null 2>&1; then
    mshellctl toast \
      "Margo" \
      "Tag ${TAG} • Tmux Active" \
      --icon "$ICON_NAME" \
      --severity positive >/dev/null 2>&1 || true
  fi
}

export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"

if [ -z "${DBUS_SESSION_BUS_ADDRESS:-}" ]; then
  export DBUS_SESSION_BUS_ADDRESS="unix:path=${XDG_RUNTIME_DIR}/bus"
fi

export PATH="$HOME/.local/bin:/usr/local/bin:/usr/bin:/bin:$PATH"

log "tagwarp started for tag $TAG"
log "DISPLAY=${DISPLAY:-empty}"
log "WAYLAND_DISPLAY=${WAYLAND_DISPLAY:-empty}"
log "XDG_RUNTIME_DIR=${XDG_RUNTIME_DIR:-empty}"
log "DBUS_SESSION_BUS_ADDRESS=${DBUS_SESSION_BUS_ADDRESS:-empty}"

if ! command -v mctl >/dev/null 2>&1; then
  log "ERROR: mctl command not found"
  exit 1
fi

for attempt in $(seq 1 30); do
  if mctl -o "$OUTPUT" tags "$MASK" >>"$LOG_FILE" 2>&1; then
    log "SUCCESS: switched $OUTPUT to tag $TAG (mask $MASK) on attempt $attempt"
    notify
    exit 0
  fi

  log "attempt $attempt failed, retrying..."
  sleep 1
done

log "ERROR: failed to switch to tag $TAG after 30 attempts"
exit 1
