# Keep zsh config under XDG.
export ZDOTDIR="$HOME/.config/zsh"

# XDG fallbacks (some systems do not set these)
: ${XDG_CONFIG_HOME:=$HOME/.config}
: ${XDG_CACHE_HOME:=$HOME/.cache}
: ${XDG_DATA_HOME:=$HOME/.local/share}
: ${XDG_STATE_HOME:=$HOME/.local/state}
export XDG_CONFIG_HOME XDG_CACHE_HOME XDG_DATA_HOME XDG_STATE_HOME

# Load the real env config if present
if [ -f "$ZDOTDIR/.zshenv" ]; then
  . "$ZDOTDIR/.zshenv"
fi
