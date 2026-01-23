# ~/.bashrc (portable; ported from nixosc)

# Interactive shell settings
case $- in
  *i*) ;;
  *) return ;;
esac

# Vi mode (match zsh viins)
set -o vi

# Better history defaults
export HISTFILESIZE=200000
export HISTSIZE=200000
export HISTCONTROL=ignoredups:ignorespace
export PROMPT_COMMAND="history -a; history -c; history -r; ${PROMPT_COMMAND:-}"

# Path helpers (preserves existing PATH)
_add_path() { case ":$PATH:" in *":$1:"*) ;; *) PATH="$1:$PATH";; esac }
_add_path "$HOME/.local/bin"
_add_path "$HOME/bin"

# fzf
if [ -f "/usr/share/fzf/key-bindings.bash" ]; then
  source "/usr/share/fzf/key-bindings.bash"
fi
if [ -f "/usr/share/fzf/completion.bash" ]; then
  source "/usr/share/fzf/completion.bash"
fi

# Starship prompt
if command -v starship >/dev/null 2>&1; then
  eval "$(starship init bash)"
fi

# Common aliases (only if wrappers exist)
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

# direnv
if command -v direnv >/dev/null 2>&1; then
  eval "$(direnv hook bash)"
fi
