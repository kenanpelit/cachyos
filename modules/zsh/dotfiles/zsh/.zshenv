# Environment variables
# Only source this once
if [[ -z "$__HM_ZSH_SESS_VARS_SOURCED" ]]; then
  export __HM_ZSH_SESS_VARS_SOURCED=1
  export BROWSER="brave"
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
  export MANWIDTH="100"
  export PAGER="less"
  export SAVEHIST="150000"
  export TERMINAL="kitty"
  export VISUAL="nvim"
  export ZDOTDIR="${HOME}/.config/zsh"
  export ZINIT_HOME="${HOME}/.local/share/zsh/zinit/zinit.git"
  export ZSH_CACHE_DIR="${HOME}/.cache/zsh"
  export ZSH_COMPDUMP="${HOME}/.cache/zsh/zcompdump-$HOST-$ZSH_VERSION"
  export ZSH_DATA_DIR="${HOME}/.local/share/zsh"
  export ZSH_DISABLE_COMPFIX="true"
  export ZSH_STATE_DIR="${HOME}/.local/state/zsh"
fi

export ZDOTDIR=${HOME}/.config/zsh
