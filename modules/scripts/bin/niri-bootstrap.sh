#!/usr/bin/env bash
# ==============================================================================
# Script: niri-bootstrap.sh
# Description: Bootstrap script for Niri session initialization.
# Usage: niri-bootstrap.sh
# ==============================================================================

set -eEuo pipefail

log() { printf "[niri-bootstrap] %s\n" "$*"; }
warn() { printf "[niri-bootstrap] WARN: %s\n" "$*" >&2; }

# Delay before init (align with systemd-driven startup)
delay_s="${NIRI_BOOT_DELAY:-1}"
if ! [[ "$delay_s" =~ ^[0-9]+$ ]]; then
  delay_s=1
fi
sleep "$delay_s"

if command -v notify-send >/dev/null 2>&1; then
  notify-send -t 2500 "Niri" "Bootstrap başladı" >/dev/null 2>&1 &
fi

# Ensure PATH includes local bin
export PATH="$HOME/.local/bin:$PATH"

# Ensure runtime + niri socket for daemons needing IPC.
if [[ -z "${XDG_RUNTIME_DIR:-}" ]]; then
  export XDG_RUNTIME_DIR="/run/user/$(id -u)"
fi
if [[ -z "${WAYLAND_DISPLAY:-}" && -n "${XDG_RUNTIME_DIR:-}" ]]; then
  for sock in "$XDG_RUNTIME_DIR"/wayland-*; do
    [[ -S "$sock" ]] || continue
    export WAYLAND_DISPLAY="$(basename "$sock")"
    break
  done
fi
if [[ -z "${NIRI_SOCKET:-}" && -n "${XDG_RUNTIME_DIR:-}" && -n "${WAYLAND_DISPLAY:-}" ]]; then
  for sock in "$XDG_RUNTIME_DIR"/niri."${WAYLAND_DISPLAY}".*.sock; do
    [[ -S "$sock" ]] || continue
    export NIRI_SOCKET="$sock"
    break
  done
fi

# Force GTK/GNOME theme settings (batched for performance)
if command -v gsettings >/dev/null 2>&1; then
    (
    # Schema might be missing in minimal installs, ignore errors
    gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark'
    gsettings set org.gnome.desktop.interface gtk-theme 'catppuccin-mocha-mauve-standard+default'
    gsettings set org.gnome.desktop.interface icon-theme 'kora'
    gsettings set org.gnome.desktop.interface cursor-theme 'catppuccin-mocha-dark-cursors'
    ) >/dev/null 2>&1 &
fi

if command -v niri-osc >/dev/null 2>&1; then
  if ! niri-osc set init; then
    warn "niri-osc set init failed"
    exit 1
  fi
else
  warn "niri-osc not found"
  exit 1
fi

finish_notify() {
  if command -v notify-send >/dev/null 2>&1;
    then
      notify-send -t 2500 "Niri" "Bootstrap bitti" >/dev/null 2>&1 &
  fi
}

finish_notify

exit 0
