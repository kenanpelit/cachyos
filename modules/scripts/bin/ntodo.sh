#!/usr/bin/env bash
# ==============================================================================
# Script: ntodo.sh
# Description: Simple todo list manager with XDG storage support.
# Usage: ntodo.sh ["task"]
# ==============================================================================
# Authorship: Kenan Pelit
# Version: 1.0.0
# Date: 2024-12-12
# License: MIT

TODO_FILE="${XDG_DATA_HOME:-$HOME/}.todo"
if [ -n "$1" ]; then
  echo "$@" >>"$TODO_FILE"
else
  "${EDITOR:-nvim}" "$TODO_FILE"
fi
