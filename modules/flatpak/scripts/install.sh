#!/usr/bin/env bash
set -euo pipefail

module_root="$(cd "$(dirname "$0")/.." && pwd)"
bin_dir="$HOME/.local/bin"
systemd_user_dir="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
flathub_url="https://flathub.org/repo/flathub.flatpakrepo"
retries="${FLATPAK_REMOTE_ADD_RETRIES:-3}"
retry_delay="${FLATPAK_REMOTE_ADD_DELAY_SEC:-5}"

log() { printf "[flatpak-install] %s\n" "$*"; }
warn() { printf "[flatpak-install] WARN: %s\n" "$*" >&2; }
die() { printf "[flatpak-install] ERROR: %s\n" "$*" >&2; exit 1; }

mkdir -p "$bin_dir" "$HOME/.config/flatpak"
chmod +x "$module_root/scripts/flatpak-managed-install" || true
ln -sf "$module_root/scripts/flatpak-managed-install" "$bin_dir/flatpak-managed-install"

# Ensure flathub remote exists early (before timer-driven installs).
if command -v flatpak >/dev/null 2>&1; then
  if ! flatpak remotes --user --columns=name 2>/dev/null | awk '{print $1}' | grep -qx flathub; then
    log "Adding flathub remote (user scope)..."
    ok=0
    for ((i = 1; i <= retries; i++)); do
      if flatpak remote-add --user --if-not-exists flathub "$flathub_url"; then
        ok=1
        break
      fi
      warn "flathub remote-add failed (attempt ${i}/${retries})"
      sleep "$retry_delay"
    done
    [[ "$ok" -eq 1 ]] || die "could not add flathub remote (user scope)"
  fi

  # Keep remote enabled in user scope.
  flatpak remote-modify --user --enable flathub >/dev/null 2>&1 || true
fi

if command -v systemctl >/dev/null 2>&1; then
  systemctl --user daemon-reload >/dev/null 2>&1 || true
  systemctl --user stop flatpak-managed-install.service >/dev/null 2>&1 || true
  systemctl --user stop flatpak-managed-install.timer >/dev/null 2>&1 || true
  systemctl --user disable flatpak-managed-install.service >/dev/null 2>&1 || true
  systemctl --user reset-failed flatpak-managed-install.service >/dev/null 2>&1 || true
  systemctl --user disable flatpak-managed-install.timer >/dev/null 2>&1 || true
  rm -f \
    "$systemd_user_dir/timers.target.wants/flatpak-managed-install.timer" \
    "$systemd_user_dir/graphical-session.target.wants/flatpak-managed-install.timer"
  systemctl --user enable --now flatpak-managed-install.timer >/dev/null 2>&1 || true
fi
