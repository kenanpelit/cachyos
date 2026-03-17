#!/usr/bin/env bash
# Bootstrap Noctalia with the compositor session environment already loaded.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

load_hypr_env() {
  local helper="${SCRIPT_DIR}/hypr-session-common.sh"
  [[ -r "$helper" ]] || helper="${SCRIPT_DIR}/hypr-session-common"
  # shellcheck source=hypr-session-common.sh
  source "$helper"
  hypr_load_session_env
  hypr_normalize_session_paths
  hypr_ensure_runtime_dir
  hypr_detect_wayland_display || true
}

load_niri_env() {
  local helper="${SCRIPT_DIR}/niri-session-common.sh"
  [[ -r "$helper" ]] || helper="${SCRIPT_DIR}/niri-session-common"
  # shellcheck source=niri-session-common.sh
  source "$helper"
  niri_load_session_env
  niri_normalize_session_paths
  niri_ensure_runtime_dir
  niri_detect_wayland_display || true
  niri_detect_socket || true
}

case "${XDG_CURRENT_DESKTOP:-${XDG_SESSION_DESKTOP:-}}" in
  Hyprland|hyprland)
    load_hypr_env
    ;;
  niri|Niri)
    load_niri_env
    ;;
esac

export XDG_ICON_THEME="${XDG_ICON_THEME:-${ICON_THEME:-kora}}"
export ICON_THEME="${ICON_THEME:-$XDG_ICON_THEME}"
export QT_ICON_THEME="${QT_ICON_THEME:-$XDG_ICON_THEME}"

if command -v gsettings >/dev/null 2>&1; then
  gsettings set org.gnome.desktop.interface icon-theme "$XDG_ICON_THEME" >/dev/null 2>&1 || true
fi

exec /usr/bin/qs -c noctalia-shell --no-duplicate
