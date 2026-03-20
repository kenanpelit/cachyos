#!/usr/bin/env bash
set -euo pipefail

grep -q '.snapshots' /proc/cmdline || exit 0
sleep 3
/usr/bin/snapper-tools --autostart || true
