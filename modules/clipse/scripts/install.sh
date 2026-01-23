#!/usr/bin/env bash
set -euo pipefail

state_home="${XDG_STATE_HOME:-$HOME/.local/state}"
mkdir -p "$HOME/.config/clipse" "$state_home/clipse"
: > "$state_home/clipse/clipse.log"
ln -sf "$state_home/clipse/clipse.log" "$HOME/.config/clipse/clipse.log"
