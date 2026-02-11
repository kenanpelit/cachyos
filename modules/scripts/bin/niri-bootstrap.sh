#!/usr/bin/env bash
set -euo pipefail

log() { printf "[niri-bootstrap] %s\n" "$*"; }
warn() { printf "[niri-bootstrap] WARN: %s\n" "$*" >&2; }

# Delay for visibility (User request)
sleep 3

if command -v notify-send >/dev/null 2>&1; then
  notify-send -t 2500 "Niri" "Bootstrap başladı" >/dev/null 2>&1 || true
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

# Force GTK/GNOME theme settings
if command -v gsettings >/dev/null 2>&1; then
    # Schema might be missing in minimal installs, ignore errors
    gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark' 2>/dev/null || true
    gsettings set org.gnome.desktop.interface gtk-theme 'catppuccin-mocha-mauve-standard+default' 2>/dev/null || true
    gsettings set org.gnome.desktop.interface icon-theme 'kora' 2>/dev/null || true
    gsettings set org.gnome.desktop.interface cursor-theme 'catppuccin-mocha-dark-cursors' 2>/dev/null || true
fi

if command -v niri-osc >/dev/null 2>&1; then
  niri-osc set init || warn "niri-osc set init failed"
  else
    warn "niri-osc not found"
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

# Start sticky daemon (new niri-osc implementation; keep nsticky as fallback)
if command -v niri-osc >/dev/null 2>&1;
  then
    start_bg niri-osc sticky
elif command -v nsticky >/dev/null 2>&1;
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

finish_notify

# Trigger keyring/GPG prompts near the end of bootstrap so user can unlock once.
if [[ "${NIRI_BOOT_PROMPT_KEYS:-1}" == "1" ]]; then
  if command -v osc-login-prompts >/dev/null 2>&1; then
    osc-login-prompts &
  else
    warn "osc-login-prompts not found; skipping login prompts"
  fi
fi

exit 0
