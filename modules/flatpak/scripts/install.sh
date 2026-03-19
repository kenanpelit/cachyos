#!/usr/bin/env bash
set -euo pipefail

module_root="$(cd "$(dirname "$0")/.." && pwd)"
repo_root="$(cd "$module_root/../.." && pwd)"
source "$repo_root/modules/base/lib/core.sh"
user_home="${USER_HOME:-$HOME}"
bin_dir="$user_home/.local/bin"
flatpak_config_dir="$user_home/.config/flatpak"
flathub_url="https://flathub.org/repo/flathub.flatpakrepo"
retries="${FLATPAK_REMOTE_ADD_RETRIES:-3}"
retry_delay="${FLATPAK_REMOTE_ADD_DELAY_SEC:-5}"

log() { printf "[flatpak-install] %s\n" "$*"; }
warn() { printf "[flatpak-install] WARN: %s\n" "$*" >&2; }
die() { printf "[flatpak-install] ERROR: %s\n" "$*" >&2; exit 1; }

run_as_user mkdir -p "$bin_dir" "$flatpak_config_dir"
chmod +x "$module_root/scripts/flatpak-managed-install" || true
run_as_user ln -sf "$module_root/scripts/flatpak-managed-install" "$bin_dir/flatpak-managed-install"

# Ensure flathub remote exists early (before timer-driven installs).
if command -v flatpak >/dev/null 2>&1; then
  if ! run_as_user flatpak remotes --user --columns=name 2>/dev/null | awk '{print $1}' | grep -qx flathub; then
    log "Adding flathub remote (user scope)..."
    ok=0
    for ((i = 1; i <= retries; i++)); do
      if run_as_user flatpak remote-add --user --if-not-exists flathub "$flathub_url"; then
        ok=1
        break
      fi
      warn "flathub remote-add failed (attempt ${i}/${retries})"
      sleep "$retry_delay"
    done
    [[ "$ok" -eq 1 ]] || die "could not add flathub remote (user scope)"
  fi

  # Keep remote enabled in user scope.
  run_as_user flatpak remote-modify --user --enable flathub >/dev/null 2>&1 || true
fi

if command -v systemctl >/dev/null 2>&1; then
  timer_unit="$module_root/dotfiles/systemd/user/flatpak-managed-install.timer"
  run_as_user systemctl --user daemon-reload >/dev/null 2>&1 || true
  run_as_user systemctl --user stop flatpak-managed-install.service >/dev/null 2>&1 || true
  run_as_user systemctl --user reset-failed flatpak-managed-install.service >/dev/null 2>&1 || true
  if ! run_as_user systemctl --user is-enabled flatpak-managed-install.timer >/dev/null 2>&1; then
    run_as_user systemctl --user enable --now "$timer_unit" >/dev/null 2>&1 || true
  elif ! run_as_user systemctl --user is-active flatpak-managed-install.timer >/dev/null 2>&1; then
    run_as_user systemctl --user start flatpak-managed-install.timer >/dev/null 2>&1 || true
  fi
fi
