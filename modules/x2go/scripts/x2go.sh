#!/usr/bin/env bash
#
# x2go — launch x2goclient.
#
# DEFAULT: native Wayland (whatever QT_QPA_PLATFORM the session ships). Under
# Wayland the Qt menus/popups are xdg-popups that the compositor positions
# correctly — this is the path that "just works".
#
# Forcing XWayland (xcb) was added earlier to dodge a connect-time SIGSEGV in
# x2goclient's X11-only paths (QX11Info -> XDefaultRootWindow on a NULL X
# display). But under XWayland the X11 override-redirect menus open in the
# wrong place (top-left corner). So xcb is now OPT-IN:
#
#   X2GO_XCB=1 x2go        # force XWayland — use ONLY if it crashes at connect
#                          # under Wayland (trade-off: menus may misplace)
#   X2GO_SCALE=1.3 x2go    # uniform Qt scale for the xcb path (DPI-unaware GUI)
#
# Any extra args are passed straight through to x2goclient.

set -euo pipefail

if ! command -v x2goclient >/dev/null 2>&1; then
	echo "x2go: x2goclient bulunamadı (paket kurulu mu?)" >&2
	exit 127
fi

# XWayland server margo brings up on :0 — only relevant for the xcb path.
export DISPLAY="${DISPLAY:-:0}"

if [ "${X2GO_XCB:-0}" = "1" ]; then
	# XWayland fallback: real X11 Display (no connect crash), but the X11
	# menus can land in the wrong spot. x2goclient's GUI is DPI-unaware
	# (x2go bug #913); force one uniform scale instead of the session's
	# per-screen auto-scaling.
	export QT_QPA_PLATFORM=xcb
	unset QT_AUTO_SCREEN_SCALE_FACTOR QT_ENABLE_HIGHDPI_SCALING QT_SCREEN_SCALE_FACTORS
	export QT_SCALE_FACTOR="${X2GO_SCALE:-1}"
fi

exec x2goclient "$@"
