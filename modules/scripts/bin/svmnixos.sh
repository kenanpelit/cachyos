#!/usr/bin/env bash
# ==============================================================================
# Script: svmnixos.sh
# Description: Compatibility shim — runs 'svm nixos' (unified VM manager, svm.sh).
# Usage: svmnixos.sh [install|start|stop|status|connect|console|reset] [options]
# ==============================================================================
exec "$(dirname "$(readlink -f "$0")")/svm.sh" nixos "$@"
