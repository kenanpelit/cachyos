#!/usr/bin/env bash
# ==============================================================================
# Script: niri-snapper-tools-check.sh
# Description: Delayed snapper-tools autostart check for Niri snapshot boots.
# ==============================================================================
set -euo pipefail

grep -q '.snapshots' /proc/cmdline || exit 0
sleep 3
/usr/bin/snapper-tools --autostart || true
