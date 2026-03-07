#!/usr/bin/env bash
# ==============================================================================
# Script: delayed-portals
# Description: Starts xdg-desktop-portal services after a specific delay.
# Usage: delayed-portals [delay_seconds]
# ==============================================================================

DELAY="${1:-40}"

# Give the system some time to breathe
sleep "$DELAY"

if command -v systemctl >/dev/null 2>&1; then
    # Restart portals to ensure they pick up the fresh environment
    systemctl --user restart xdg-desktop-portal-gnome.service 2>/dev/null || true
    systemctl --user restart xdg-desktop-portal-gtk.service 2>/dev/null || true
    systemctl --user restart xdg-desktop-portal.service 2>/dev/null || true
fi
