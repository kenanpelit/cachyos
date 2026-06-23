#!/usr/bin/env bash
#
# x2go — launch x2goclient under XWayland (xcb), not native Wayland.
#
# x2goclient is an X11-only Qt5 app (QX11Info + raw Xlib). Under margo's
# Wayland Qt platform plugin (the session ships QT_QPA_PLATFORM="wayland;xcb",
# so Qt picks wayland) QX11Info::display() returns NULL and the client
# SIGSEGVs in XDefaultRootWindow the instant its session-poll timer fires —
# i.e. right as a session connects. Pinning the xcb platform makes it talk to
# margo's XWayland server (DISPLAY=:0), where it has a real X11 Display.
#
# Any extra args are passed straight through to x2goclient.

set -euo pipefail

if ! command -v x2goclient >/dev/null 2>&1; then
	echo "x2go: x2goclient bulunamadı (paket kurulu mu?)" >&2
	exit 127
fi

# margo brings XWayland up on :0; honour whatever DISPLAY is already set.
export DISPLAY="${DISPLAY:-:0}"
export QT_QPA_PLATFORM=xcb

exec x2goclient "$@"
