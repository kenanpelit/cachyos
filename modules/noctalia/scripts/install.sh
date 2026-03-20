#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
MODULE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
source "$REPO_ROOT/modules/base/lib/core.sh"

noctalia_template_dir="$MODULE_DIR/dotfiles/noctalia"
noctalia_config_dir="$USER_HOME/.config/noctalia"

ensure_real_dir() {
  local dir="$1"
  if run_as_user test -L "$dir"; then
    run_as_user rm -f "$dir"
  fi
  run_as_user mkdir -p "$dir"
}

ensure_writable_file_from_template() {
  local rel="$1"
  local src="$noctalia_template_dir/$rel"
  local dst="$noctalia_config_dir/$rel"
  local parent
  parent="$(dirname "$dst")"

  [[ -r "$src" ]] || return 0

  run_as_user mkdir -p "$parent"
  if run_as_user test -L "$dst"; then
    run_as_user rm -f "$dst"
  fi
  if ! run_as_user test -f "$dst"; then
    run_as_user install -m 644 "$src" "$dst"
  fi
}

sync_tree_from_template() {
  local rel="$1"
  local src="$noctalia_template_dir/$rel/"
  local dst="$noctalia_config_dir/$rel/"

  ensure_real_dir "$noctalia_config_dir/$rel"

  if command -v rsync >/dev/null 2>&1; then
    run_as_user rsync -a --delete \
      --exclude 'clipper/pinned.json' \
      --exclude 'clipper/notecards/' \
      "$src" "$dst"
  else
    run_as_user cp -a "$src/." "$dst"
  fi
}

ensure_real_dir "$noctalia_config_dir"
sync_tree_from_template "colorschemes"
sync_tree_from_template "plugins"
ensure_writable_file_from_template "colors.json"
ensure_writable_file_from_template "settings.json"
ensure_writable_file_from_template "settings.json.bak"
ensure_writable_file_from_template "plugins.json"

if command -v systemctl >/dev/null 2>&1; then
  run_as_user systemctl --user daemon-reload >/dev/null 2>&1 || true
  if run_as_user systemctl --user is-active noctalia.service >/dev/null 2>&1; then
    run_as_user systemctl --user try-restart noctalia.service >/dev/null 2>&1 || true
  fi
fi

# Noctalia ships a polkit plugin upstream, but Hyprland/Niri sessions already
# use dedicated systemd-managed polkit agents. Remove any stale local copy so
# plugin updates cannot reintroduce the duplicate agent.
run_as_user rm -rf "$USER_HOME/.config/noctalia/plugins/polkit-agent" || true
run_as_user mkdir -p "$USER_HOME/.config/noctalia/plugins/clipper/notecards"
run_as_user /usr/bin/sh -c 'pinned="$1"; [ -f "$pinned" ] || printf "%s\n" "{\"items\":[]}" > "$pinned"' _ "$USER_HOME/.config/noctalia/plugins/clipper/pinned.json"

# Not: settings.json manipülasyonu dosya yapısını bozabileceği ve dcli sync 
# çakışması yaratabileceği için devre dışı bırakılmıştır.
# Ayarlar artık sadece Noctalia UI üzerinden yönetilmelidir.
