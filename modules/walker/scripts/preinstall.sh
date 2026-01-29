#!/usr/bin/env bash
set -euo pipefail

# Remove conflicting elephant packages before installing elephant-all-bin.
if command -v pacman >/dev/null 2>&1; then
  if pacman -Qq elephant >/dev/null 2>&1; then
    sudo pacman -Rns --noconfirm elephant
  fi
  if pacman -Qq elephant-bin >/dev/null 2>&1; then
    sudo pacman -Rns --noconfirm elephant-bin
  fi
fi
