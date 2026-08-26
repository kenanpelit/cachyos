# Canonical Zsh environment file.
# This file is used for both ~/.zshenv and ~/.config/zsh/.zshenv so there is a
# single source of truth for shell environment setup.

# XDG fallbacks (some systems do not set these)
: ${XDG_CONFIG_HOME:=$HOME/.config}
: ${XDG_CACHE_HOME:=$HOME/.cache}
: ${XDG_DATA_HOME:=$HOME/.local/share}
: ${XDG_STATE_HOME:=$HOME/.local/state}
export XDG_CONFIG_HOME XDG_CACHE_HOME XDG_DATA_HOME XDG_STATE_HOME

# Keep zsh config under XDG.
export ZDOTDIR="${XDG_CONFIG_HOME}/zsh"
# mdots: declarative config repo lives at ~/.cachy, reached via the ~/.config/mdots
# symlink (the canonical config path).
export MDOTS_CONFIG_DIR="$HOME/.config/mdots"
export MDOTS_SOPS_KEY_PATH="$HOME/.config/sops/age/keys.txt"

# Environment variables
# Only source this once
if [[ -z "$__HM_ZSH_SESS_VARS_SOURCED" ]]; then
  export __HM_ZSH_SESS_VARS_SOURCED=1
  case "${BROWSER:-}" in
    ""|brave|start-brave-kenp|start-chrome-kenp|bravectl|start-helium-kenp|heliumctl)
      if command -v start-chrome-kenp >/dev/null 2>&1; then
        export BROWSER="start-chrome-kenp"
      elif command -v start-brave-kenp >/dev/null 2>&1; then
        export BROWSER="start-brave-kenp"
      elif command -v start-helium-kenp >/dev/null 2>&1; then
        export BROWSER="start-helium-kenp"
      elif command -v heliumctl >/dev/null 2>&1; then
        export BROWSER="heliumctl"
      elif command -v bravectl >/dev/null 2>&1; then
        export BROWSER="bravectl"
      else
        export BROWSER="brave"
      fi
      ;;
  esac
  export COMPLETION_WAITING_DOTS="true"
  export EDITOR="nvim"
  export HISTFILE="${HOME}/.config/zsh/history"
  export HISTSIZE="200000"
  export LANG="en_US.UTF-8"
  export LC_ALL="en_US.UTF-8"
  export LESS="-R --use-color -Dd+r -Du+b -DS+y -DP+k"
  export LESSCHARSET="utf-8"
  export LESSHISTFILE="-"
  export MANPAGER="sh -c 'col -bx | bat -l man -p'"
  # groff'u backspace-overstrike'a zorla (SGR yerine) — col|bat pager
  # aksi halde escape kodlarını "4mFOO24m" gibi sızdırır.
  export MANROFFOPT="-c"
  export MANWIDTH="100"
  export PAGER="less"
  export SAVEHIST="150000"
  export TERMINAL="kitty"
  export VISUAL="nvim"
  export ZINIT_HOME="${HOME}/.local/share/zsh/zinit/zinit.git"
  export ZSH_CACHE_DIR="${HOME}/.cache/zsh"
  export ZSH_COMPDUMP="${HOME}/.cache/zsh/zcompdump-$HOST-$ZSH_VERSION"
  export ZSH_DATA_DIR="${HOME}/.local/share/zsh"
  export ZSH_DISABLE_COMPFIX="true"
  export ZSH_STATE_DIR="${HOME}/.local/state/zsh"
fi
