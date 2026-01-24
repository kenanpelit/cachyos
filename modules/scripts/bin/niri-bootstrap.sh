#!/usr/bin/env bash
set -euo pipefail

log() { printf "[niri-bootstrap] %s\n" "$*"; }
warn() { printf "[niri-bootstrap] WARN: %s\n" "$*" >&2; }

if command -v notify-send >/dev/null 2>&1; then
  notify-send -t 2500 "Niri" "Bootstrap başladı" >/dev/null 2>&1 || true
fi

# Ensure PATH includes local bin
export PATH="$HOME/.local/bin:$PATH"

# Force GTK/GNOME theme settings
if command -v gsettings >/dev/null 2>&1; then
    # Schema might be missing in minimal installs, ignore errors
    gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark' 2>/dev/null || true
    gsettings set org.gnome.desktop.interface gtk-theme 'catppuccin-mocha-mauve-standard+default' 2>/dev/null || true
    gsettings set org.gnome.desktop.interface icon-theme 'candy-icons' 2>/dev/null || true
    gsettings set org.gnome.desktop.interface cursor-theme 'catppuccin-mocha-dark-cursors' 2>/dev/null || true
fi

if command -v niri-set >/dev/null 2>&1; then
  niri-set init || warn "niri-set init failed"
  else
    warn "niri-set not found"
fi

# Optional Bluetooth auto-connect (delayed, non-blocking).
# We assume enabled if the script exists
if command -v bluetooth_toggle >/dev/null 2>&1;
  then
    (
      delay_s="${NIRI_BOOT_BT_DELAY:-5}"
      timeout_s="${NIRI_BOOT_BT_TIMEOUT:-30}"
      sleep "$delay_s"
      if command -v timeout >/dev/null 2>&1;
        then
          timeout "${timeout_s}s" bluetooth_toggle --connect || true
        else
          bluetooth_toggle --connect || true
      fi
    ) &
fi

pids=()
start_bg() {
  "$@" &
  pids+=("$!")
  log "started: $* (pid=${!})"
}

# Start nsticky if available
if command -v nsticky >/dev/null 2>&1;
  then
    start_bg nsticky
fi

# Start niriusd if available (disabled due to incompatibility)
# if command -v niriusd >/dev/null 2>&1;
#   then
#     start_bg niriusd
# fi

# Start niriuswitcher if available
if command -v niriuswitcher >/dev/null 2>&1;
  then
    start_bg niriuswitcher
fi

finish_notify() {
  if command -v notify-send >/dev/null 2>&1;
    then
      notify-send -t 2500 "Niri" "Bootstrap bitti" >/dev/null 2>&1 || true
  fi
}

if [[ "${#pids[@]}" -eq 0 ]]; then
  log "no daemons to supervise; exiting"
  finish_notify
  exit 0
fi

trap 'warn "stopping"; kill "${pids[@]}" 2>/dev/null || true; wait "${pids[@]}" 2>/dev/null || true; finish_notify' INT TERM EXIT

# If any daemon exits, restart the whole unit for consistency.
if wait -n "${pids[@]}"; then
  warn "daemon exited; restarting unit"
  exit 1
fi
