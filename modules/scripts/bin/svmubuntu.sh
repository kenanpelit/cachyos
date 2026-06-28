#!/usr/bin/env bash
# ==============================================================================
# Script: svmubuntu.sh
# Description: Compatibility shim — runs 'svm ubuntu' (unified VM manager, svm.sh).
# Usage: svmubuntu.sh [install|start|stop|status|connect|console|reset] [options]
# ==============================================================================
exec "$(dirname "$(readlink -f "$0")")/svm.sh" ubuntu "$@"
