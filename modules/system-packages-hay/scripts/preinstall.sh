#!/usr/bin/env bash
set -euo pipefail

# neovim-symlinks conflicts with packages that provide the classic vi/vim
# entrypoints. Remove them before the package batch begins so dcli can keep
# running non-interactively.
if command -v pacman >/dev/null 2>&1; then
  for pkg in vim vi-vim-symlink; do
    if pacman -Qq "$pkg" >/dev/null 2>&1; then
      pacman -Rns --noconfirm "$pkg"
    fi
  done
fi
