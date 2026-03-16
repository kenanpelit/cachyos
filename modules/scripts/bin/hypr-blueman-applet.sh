#!/usr/bin/env bash
set -euo pipefail

log() { printf '[hypr-blueman-applet] %s\n' "$*" >&2; }

wait_for_noctalia() {
  command -v systemctl >/dev/null 2>&1 || return 0

  local deadline=$((SECONDS + 20))
  while (( SECONDS < deadline )); do
    if systemctl --user --quiet is-active noctalia.service 2>/dev/null; then
      return 0
    fi
    sleep 1
  done

  log "Noctalia did not report active before timeout; continuing"
  return 0
}

wait_for_status_notifier_watcher() {
  command -v gdbus >/dev/null 2>&1 || return 0

  local deadline=$((SECONDS + 20))
  while (( SECONDS < deadline )); do
    if gdbus introspect \
      --session \
      --dest org.kde.StatusNotifierWatcher \
      --object-path /StatusNotifierWatcher \
      >/dev/null 2>&1; then
      sleep 2
      return 0
    fi
    sleep 1
  done

  log "StatusNotifierWatcher not available before timeout; continuing"
  return 0
}

# Blueman imports some X11-only plugins before honoring plugin-list, which
# produces a known Wayland-only false-positive warning. Filter only those
# specific lines and keep every other warning/error visible in the journal.
wait_for_noctalia
wait_for_status_notifier_watcher

exec /usr/bin/blueman-applet "$@" 2> >(
  grep -Ev 'Failed to start plugin GameControllerWakelock: Only X11 platform is supported|gtk_widget_get_scale_factor: assertion .GTK_IS_WIDGET \(widget\) failed' >&2
)
