#!/usr/bin/env bash
# ==============================================================================
# Script: mango-blueman-applet.sh
# Description: Wayland-safe Blueman applet wrapper for Mango sessions.
# ==============================================================================
set -euo pipefail

log() { printf '[mango-blueman-applet] %s\n' "$*" >&2; }

if command -v dconf >/dev/null 2>&1; then
	dconf write /org/blueman/general/plugin-list "${BLUEMAN_PLUGIN_LIST:-['!TransferService', '!GameControllerWakelock', '!PPPSupport', '!DhcpClient']}" >/dev/null 2>&1 || true
fi

# Blueman imports some X11-only plugins before honoring plugin-list, which
# produces a known Wayland-only false-positive warning. Filter only those
# specific lines and keep every other warning/error visible in the journal.
log "launching blueman-applet after Mango readiness gates"

exec /usr/bin/blueman-applet "$@" 2> >(
	grep -Ev 'Failed to start plugin GameControllerWakelock: Only X11 platform is supported|gtk_widget_get_scale_factor: assertion .GTK_IS_WIDGET \(widget\) failed' >&2
)
