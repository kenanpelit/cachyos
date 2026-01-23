#!/usr/bin/env bash
# niri-start - Daily startup sequence for Niri session
# Generated/Managed via dcli

# Ensure we are using the correct local bin path
export PATH="$HOME/.local/bin:$PATH"

# Log the start attempt
mkdir -p "$HOME/.logs/semsumo"
echo "Starting daily routine at $(date)" >> "$HOME/.logs/semsumo/niri-start.log"

# Launch daily apps via semsumo
# We use full path to be safe when called from keybinds
if command -v semsumo >/dev/null 2>&1; then
    exec semsumo launch --daily -all
else
    # Fallback if not in path yet
    exec "$HOME/.local/bin/semsumo" launch --daily -all
fi
