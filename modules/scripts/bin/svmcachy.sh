#!/usr/bin/env bash
# ==============================================================================
# Script: svmcachy.sh
# Description: Compatibility shim — runs 'svm cachy' (unified VM manager, svm.sh).
# Usage: svmcachy.sh [install|start|stop|status|connect|console|reset] [options]
# ==============================================================================
exec "$(dirname "$(readlink -f "$0")")/svm.sh" cachy "$@"
