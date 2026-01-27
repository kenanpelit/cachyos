# ~/.bashrc (portable)

# ----------------------------------------------------------------------
# Interactive shell settings
# ----------------------------------------------------------------------
case $- in
  *i*) ;;
  *) return ;;
esac

# ----------------------------------------------------------------------
# XDG base directories (fallbacks)
# ----------------------------------------------------------------------
: "${XDG_CONFIG_HOME:=$HOME/.config}"
: "${XDG_CACHE_HOME:=$HOME/.cache}"
: "${XDG_DATA_HOME:=$HOME/.local/share}"
: "${XDG_STATE_HOME:=$HOME/.local/state}"
export XDG_CONFIG_HOME XDG_CACHE_HOME XDG_DATA_HOME XDG_STATE_HOME

# ----------------------------------------------------------------------
# History configuration
# ----------------------------------------------------------------------
HISTFILE="$XDG_STATE_HOME/bash/history"
mkdir -p "$(dirname "$HISTFILE")"
export HISTFILE
export HISTFILESIZE=200000
export HISTSIZE=200000
export HISTCONTROL=ignoredups:ignorespace
shopt -s histappend cmdhist checkwinsize
PROMPT_COMMAND="history -a; history -c; history -r; ${PROMPT_COMMAND:-}"

# ----------------------------------------------------------------------
# Input mode (match zsh viins)
# ----------------------------------------------------------------------
set -o vi

# ----------------------------------------------------------------------
# PATH helpers (preserve existing PATH, avoid duplicates)
# ----------------------------------------------------------------------
_add_path() { case ":$PATH:" in *":$1:"*) ;; *) PATH="$1:$PATH";; esac }
_add_path "$HOME/.local/bin"
_add_path "$HOME/bin"
_add_path "$HOME/.iptv/bin"
_add_path "/usr/local/bin"
unset -f _add_path

# ----------------------------------------------------------------------
# Completions
# ----------------------------------------------------------------------
if [ -r /usr/share/bash-completion/bash_completion ]; then
  # shellcheck disable=SC1091
  . /usr/share/bash-completion/bash_completion
elif [ -r /etc/bash_completion ]; then
  # shellcheck disable=SC1091
  . /etc/bash_completion
fi

# ----------------------------------------------------------------------
# fzf
# ----------------------------------------------------------------------
if [ -f /usr/share/fzf/key-bindings.bash ]; then
  # shellcheck disable=SC1091
  . /usr/share/fzf/key-bindings.bash
fi
if [ -f /usr/share/fzf/completion.bash ]; then
  # shellcheck disable=SC1091
  . /usr/share/fzf/completion.bash
fi

# ----------------------------------------------------------------------
# Prompt
# ----------------------------------------------------------------------
if command -v starship >/dev/null 2>&1; then
  eval "$(starship init bash)"
fi

# ----------------------------------------------------------------------
# Aliases (only if wrappers exist)
# ----------------------------------------------------------------------
if command -v brave-launcher >/dev/null 2>&1; then
  alias brave=brave-launcher
fi
if command -v chrome-launcher >/dev/null 2>&1; then
  alias chrome=chrome-launcher
fi

# Transmission helpers
if command -v transmission-remote >/dev/null 2>&1; then
  alias tr-list='transmission-remote -l'
  alias tr-add='transmission-remote -a'
  alias tr-remove='transmission-remote -r'
  alias tr-info='transmission-remote -i'
fi

# ----------------------------------------------------------------------
# Tools
# ----------------------------------------------------------------------
# yazi: jump to last directory
yy() {
  local tmp
  tmp="$(mktemp -t "yazi-cwd.XXXXX")"
  yazi "$@" --cwd-file="$tmp"
  if cwd="$(<"$tmp")" && [ -n "$cwd" ] && [ "$cwd" != "$PWD" ]; then
    builtin cd -- "$cwd"
  fi
  rm -f -- "$tmp"
}

# GPG: keep agent tied to current TTY
if command -v gpg-connect-agent >/dev/null 2>&1; then
  GPG_TTY="$(tty)"
  export GPG_TTY
  gpg-connect-agent --quiet updatestartuptty /bye >/dev/null 2>&1 || true
fi

# direnv (optional)
if command -v direnv >/dev/null 2>&1; then
  eval "$(direnv hook bash)"
fi
