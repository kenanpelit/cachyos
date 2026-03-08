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

wait_for_niri_ready() {
  local i
  for i in $(seq 1 300); do
    if command -v niri >/dev/null 2>&1; then
      if [[ -n "${NIRI_SOCKET:-}" ]]; then
        NIRI_SOCKET="${NIRI_SOCKET}" niri msg version >/dev/null 2>&1 && return 0
      else
        niri msg version >/dev/null 2>&1 && return 0
      fi
    fi
    sleep 0.05
  done
  return 1
}

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
  if ! wait_for_niri_ready; then
    warn "niri IPC readiness timeout"
    exit 1
  fi

  if ! niri-osc set init; then
    warn "niri-osc set init failed"
    exit 1
  fi

  # Apply portal backend policy after the compositor and env are fully ready.
  if command -v delayed-portals >/dev/null 2>&1; then
    delayed-portals 0 || warn "delayed-portals failed"
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
