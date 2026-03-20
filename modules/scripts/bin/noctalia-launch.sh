#!/usr/bin/env bash
# Bootstrap Noctalia with the compositor session environment already loaded.

set -euo pipefail

SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(cd -- "$(dirname -- "$SCRIPT_PATH")" && pwd -P)"
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/../.." && pwd -P)"
NOCTALIA_PLUGIN_TEMPLATE="${REPO_ROOT}/modules/noctalia/dotfiles/noctalia/plugins.json"
NOCTALIA_PLUGIN_STATE="${HOME}/.config/noctalia/plugins.json"
NOCTALIA_PLUGIN_SOURCE_URL="https://github.com/noctalia-dev/noctalia-plugins"

ensure_noctalia_plugin_state() {
  mkdir -p "${HOME}/.config/noctalia"

  if [[ -L "${NOCTALIA_PLUGIN_STATE}" ]]; then
    local tmp
    tmp="$(mktemp "${XDG_RUNTIME_DIR:-/tmp}/noctalia-plugins.XXXXXX")"
    cat "${NOCTALIA_PLUGIN_STATE}" > "${tmp}" 2>/dev/null || cat "${NOCTALIA_PLUGIN_TEMPLATE}" > "${tmp}"
    rm -f "${NOCTALIA_PLUGIN_STATE}"
    mv "${tmp}" "${NOCTALIA_PLUGIN_STATE}"
  fi

  if [[ ! -f "${NOCTALIA_PLUGIN_STATE}" && -r "${NOCTALIA_PLUGIN_TEMPLATE}" ]]; then
    install -m 644 "${NOCTALIA_PLUGIN_TEMPLATE}" "${NOCTALIA_PLUGIN_STATE}"
  fi
}

apply_noctalia_plugin_overrides() {
  local session_name="${1:-}"
  local enable_niri_plugins="false"
  local enable_hypr_plugins="false"
  local tmp

  case "${session_name}" in
    hyprland)
      enable_hypr_plugins="true"
      ;;
    niri)
      enable_niri_plugins="true"
      ;;
    *)
      return 0
      ;;
  esac

  command -v jq >/dev/null 2>&1 || return 0
  ensure_noctalia_plugin_state
  [[ -f "${NOCTALIA_PLUGIN_STATE}" ]] || return 0

  tmp="$(mktemp "${XDG_RUNTIME_DIR:-/tmp}/noctalia-plugins.XXXXXX")"
  if jq \
    --argjson enable_niri "${enable_niri_plugins}" \
    --argjson enable_hypr "${enable_hypr_plugins}" \
    --arg source_url "${NOCTALIA_PLUGIN_SOURCE_URL}" \
    '
      def set_state($container; $id; $enabled):
        .[$container][$id] = (((.[$container][$id] // {}) + {enabled: $enabled})
          | if has("sourceUrl") then . else . + {sourceUrl: $source_url} end);

      if has("states") then
        set_state("states"; "niri-auto-tile"; $enable_niri)
        | set_state("states"; "niri-overview-launcher"; $enable_niri)
        | set_state("states"; "screen-shot-and-record"; $enable_hypr)
        | set_state("states"; "special-workspaces"; $enable_hypr)
      elif has("plugins") then
        set_state("plugins"; "niri-auto-tile"; $enable_niri)
        | set_state("plugins"; "niri-overview-launcher"; $enable_niri)
        | set_state("plugins"; "screen-shot-and-record"; $enable_hypr)
        | set_state("plugins"; "special-workspaces"; $enable_hypr)
      else
        . + {states: {}}
        | set_state("states"; "niri-auto-tile"; $enable_niri)
        | set_state("states"; "niri-overview-launcher"; $enable_niri)
        | set_state("states"; "screen-shot-and-record"; $enable_hypr)
        | set_state("states"; "special-workspaces"; $enable_hypr)
      end
    ' "${NOCTALIA_PLUGIN_STATE}" > "${tmp}"; then
    mv "${tmp}" "${NOCTALIA_PLUGIN_STATE}"
  else
    rm -f "${tmp}"
  fi
}

load_hypr_env() {
  local helper="${SCRIPT_DIR}/hypr-session-common.sh"
  [[ -r "$helper" ]] || helper="${SCRIPT_DIR}/hypr-session-common"
  # shellcheck source=hypr-session-common.sh
  source "$helper"
  hypr_clear_foreign_session_env
  hypr_load_session_env
  hypr_normalize_session_paths
  hypr_ensure_runtime_dir
  export XDG_CURRENT_DESKTOP="${XDG_CURRENT_DESKTOP:-Hyprland}"
  export XDG_SESSION_TYPE="${XDG_SESSION_TYPE:-wayland}"
  export XDG_SESSION_DESKTOP="${XDG_SESSION_DESKTOP:-Hyprland}"
  export DESKTOP_SESSION="${DESKTOP_SESSION:-hyprland-uwsm}"
  hypr_detect_wayland_display || true
  hypr_detect_instance_signature || true
}

load_niri_env() {
  local helper="${SCRIPT_DIR}/niri-session-common.sh"
  [[ -r "$helper" ]] || helper="${SCRIPT_DIR}/niri-session-common"
  # shellcheck source=niri-session-common.sh
  source "$helper"
  niri_clear_foreign_session_env
  niri_load_session_env
  niri_normalize_session_paths
  niri_ensure_runtime_dir
  niri_ensure_session_identity
  export DESKTOP_SESSION="${DESKTOP_SESSION:-niri-uwsm}"
  niri_detect_wayland_display || true
  niri_detect_socket || true
}

session_backend=""

case "${XDG_CURRENT_DESKTOP:-${XDG_SESSION_DESKTOP:-}}" in
  Hyprland|hyprland)
    load_hypr_env
    session_backend="hyprland"
    ;;
  niri|Niri)
    load_niri_env
    session_backend="niri"
    ;;
esac

apply_noctalia_plugin_overrides "${session_backend}"

export XDG_ICON_THEME="${XDG_ICON_THEME:-${ICON_THEME:-kora}}"
export ICON_THEME="${ICON_THEME:-$XDG_ICON_THEME}"
export QT_ICON_THEME="${QT_ICON_THEME:-$XDG_ICON_THEME}"

if command -v gsettings >/dev/null 2>&1; then
  gsettings set org.gnome.desktop.interface icon-theme "$XDG_ICON_THEME" >/dev/null 2>&1 || true
fi

export XDG_DATA_DIRS="/usr/share:/usr/local/share:${HOME}/.local/share:${XDG_DATA_DIRS:-}"
export QT_QPA_PLATFORMTHEME="gtk3"

exec /usr/bin/qs -c noctalia-shell --no-duplicate
