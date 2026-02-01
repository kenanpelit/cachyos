#!/usr/bin/env bash
set -euo pipefail

LOG_FILE="${XDG_CACHE_HOME:-$HOME/.cache}/osc-mullvad-toggle.log"
mkdir -p "$(dirname "$LOG_FILE")"

log() {
  printf "%s %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >>"$LOG_FILE"
}

# Keep log size sane (last 200 lines).
if [ -f "$LOG_FILE" ] && [ "$(wc -l <"$LOG_FILE")" -gt 200 ]; then
  tail -n 200 "$LOG_FILE" >"${LOG_FILE}.tmp" && mv "${LOG_FILE}.tmp" "$LOG_FILE"
fi

log "triggered: uid=$(id -u) tty=$(tty 2>/dev/null || echo none)"
log "env: DISPLAY=${DISPLAY-} WAYLAND_DISPLAY=${WAYLAND_DISPLAY-} XDG_RUNTIME_DIR=${XDG_RUNTIME_DIR-}"

CMD=(/home/kenan/.local/bin/osc-mullvad toggle --with-blocky)

if [ "$(id -u)" -eq 0 ]; then
  log "running as root"
  "${CMD[@]}"
  exit 0
fi

# Use pkexec with environment so polkit has session context.
if command -v pkexec >/dev/null 2>&1; then
  log "pkexec running"
  /usr/bin/pkexec /usr/bin/env \
    DISPLAY="${DISPLAY-}" \
    WAYLAND_DISPLAY="${WAYLAND_DISPLAY-}" \
    XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR-}" \
    DBUS_SESSION_BUS_ADDRESS="${DBUS_SESSION_BUS_ADDRESS-}" \
    PATH="/usr/sbin:/usr/bin:/sbin:/bin" \
    /bin/bash -lc \
    "OSC_MULLVAD_NO_NOTIFY=1 /home/kenan/.local/bin/osc-mullvad toggle --with-blocky >>/tmp/osc-mullvad-toggle.root.log 2>&1"
  rc=$?
  log "pkexec exit=${rc}"
  exit "${rc}"
fi

log "pkexec not found"
exit 1
