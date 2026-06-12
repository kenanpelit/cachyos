#!/usr/bin/env bash

# tagwarp
# Switch Margo to a target tag reliably during startup or manual use.

set -u

TAG="${1:-2}"
APP_NAME="MARGO"
ICON_NAME="view-grid-symbolic"
LOG_FILE="${XDG_CACHE_HOME:-$HOME/.cache}/tagwarp.log"

mkdir -p "$(dirname "$LOG_FILE")"

log() {
  printf '[%s] %s\n' "$(date '+%F %T')" "$*" >>"$LOG_FILE"
}

notify() {
  if command -v notify-send >/dev/null 2>&1; then
    notify-send \
      -a "$APP_NAME" \
      -t 5000 \
      -i "$ICON_NAME" \
      "Margo" \
      "Tag ${TAG} • Tmux Active" >/dev/null 2>&1 || true
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
  if mctl tags "$TAG" >>"$LOG_FILE" 2>&1; then
    log "SUCCESS: switched to tag $TAG on attempt $attempt"
    notify
    exit 0
  fi

  log "attempt $attempt failed, retrying..."
  sleep 1
done

log "ERROR: failed to switch to tag $TAG after 30 attempts"
exit 1
