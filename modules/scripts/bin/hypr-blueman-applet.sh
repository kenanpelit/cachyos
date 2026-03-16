#!/usr/bin/env bash
set -euo pipefail

# Blueman imports some X11-only plugins before honoring plugin-list, which
# produces a known Wayland-only false-positive warning. Filter only those
# specific lines and keep every other warning/error visible in the journal.
exec /usr/bin/blueman-applet "$@" 2> >(
  grep -Ev 'Failed to start plugin GameControllerWakelock: Only X11 platform is supported|gtk_widget_get_scale_factor: assertion .GTK_IS_WIDGET \(widget\) failed' >&2
)
