#!/usr/bin/env bash
# ==============================================================================
# Script: svmarch.sh
# Description: Compatibility shim — runs 'svm arch' (unified VM manager, svm.sh).
# Usage: svmarch.sh [install|start|stop|status|connect|console|reset] [options]
# ==============================================================================
exec "$(dirname "$(readlink -f "$0")")/svm.sh" arch "$@"
