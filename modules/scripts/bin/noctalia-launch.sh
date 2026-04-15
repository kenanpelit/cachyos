#!/usr/bin/env bash
# ==============================================================================
# Script: noctalia-launch.sh
# Description: Prepare session-specific Noctalia state and launch the shell.
# ==============================================================================

set -euo pipefail

SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(cd -- "$(dirname -- "$SCRIPT_PATH")" && pwd -P)"
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/../.." && pwd -P)"
NOCTALIA_CONFIG_DIR="${HOME}/.config/noctalia"
NOCTALIA_PLUGIN_TEMPLATE="${REPO_ROOT}/modules/noctalia/dotfiles/noctalia/plugins.json"
NOCTALIA_PLUGIN_STATE="${NOCTALIA_CONFIG_DIR}/plugins.json"
NOCTALIA_SETTINGS_TEMPLATE="${REPO_ROOT}/modules/noctalia/dotfiles/noctalia/settings.json"
NOCTALIA_SETTINGS_STATE="${NOCTALIA_CONFIG_DIR}/settings.json"
NOCTALIA_PLUGIN_SOURCE_URL="https://github.com/noctalia-dev/noctalia-plugins"
NOCTALIA_REMOVED_PLUGIN_ID="niri-auto-tile"
NOCTALIA_REMOVED_PLUGIN_WIDGET_ID="plugin:niri-auto-tile"
NOCTALIA_REMOVED_PLUGIN_DIR="${NOCTALIA_CONFIG_DIR}/plugins/${NOCTALIA_REMOVED_PLUGIN_ID}"
NOCTALIA_MANGO_LAYOUT_WIDGET_JSON='{"defaultSettings":{"monitorOrder":[]},"id":"plugin:mangowc-layout-switcher"}'

replace_file_if_changed() {
  local source_file="$1"
  local target_file="$2"

  if [[ -f "${target_file}" ]] && cmp -s "${source_file}" "${target_file}"; then
    rm -f "${source_file}"
    return 1
  fi

  mv "${source_file}" "${target_file}"
  return 0
}

ensure_noctalia_plugin_state() {
  mkdir -p "${NOCTALIA_CONFIG_DIR}"

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

ensure_noctalia_settings_state() {
  mkdir -p "${NOCTALIA_CONFIG_DIR}"

  if [[ ! -f "${NOCTALIA_SETTINGS_STATE}" && -r "${NOCTALIA_SETTINGS_TEMPLATE}" ]]; then
    install -m 644 "${NOCTALIA_SETTINGS_TEMPLATE}" "${NOCTALIA_SETTINGS_STATE}"
  fi
}

prune_removed_noctalia_plugin_state() {
  local tmp

  rm -rf "${NOCTALIA_REMOVED_PLUGIN_DIR}"

  command -v jq >/dev/null 2>&1 || return 0

  if [[ -f "${NOCTALIA_PLUGIN_STATE}" ]]; then
    tmp="$(mktemp "${XDG_RUNTIME_DIR:-/tmp}/noctalia-prune-plugins.XXXXXX")"
    if jq --arg id "${NOCTALIA_REMOVED_PLUGIN_ID}" '
      if has("states") then .states |= del(.[$id]) else . end
      | if has("plugins") then .plugins |= del(.[$id]) else . end
    ' "${NOCTALIA_PLUGIN_STATE}" > "${tmp}"; then
      replace_file_if_changed "${tmp}" "${NOCTALIA_PLUGIN_STATE}" || true
    else
      rm -f "${tmp}"
    fi
  fi

  if [[ -f "${NOCTALIA_SETTINGS_STATE}" ]]; then
    tmp="$(mktemp "${XDG_RUNTIME_DIR:-/tmp}/noctalia-prune-settings.XXXXXX")"
    if jq --arg widget_id "${NOCTALIA_REMOVED_PLUGIN_WIDGET_ID}" '
      if .bar?.right?.widgets then
        .bar.right.widgets |= map(select((.id // "") != $widget_id))
      else
        .
      end
    ' "${NOCTALIA_SETTINGS_STATE}" > "${tmp}"; then
      replace_file_if_changed "${tmp}" "${NOCTALIA_SETTINGS_STATE}" || true
    else
      rm -f "${tmp}"
    fi
  fi
}

apply_noctalia_plugin_overrides() {
  local session_name="${1:-}"
  local enable_niri_plugins="false"
  local enable_hypr_plugins="false"
  local enable_mango_plugins="false"
  local tmp

  case "${session_name}" in
    hyprland)
      enable_hypr_plugins="true"
      ;;
    niri)
      enable_niri_plugins="true"
      ;;
    mango)
      enable_mango_plugins="true"
      ;;
  esac

  command -v jq >/dev/null 2>&1 || return 0
  ensure_noctalia_plugin_state
  [[ -f "${NOCTALIA_PLUGIN_STATE}" ]] || return 0

  tmp="$(mktemp "${XDG_RUNTIME_DIR:-/tmp}/noctalia-plugins.XXXXXX")"
  if jq \
    --argjson enable_niri "${enable_niri_plugins}" \
    --argjson enable_hypr "${enable_hypr_plugins}" \
    --argjson enable_mango "${enable_mango_plugins}" \
    --arg source_url "${NOCTALIA_PLUGIN_SOURCE_URL}" \
    '
      def set_state($container; $id; $enabled):
        .[$container][$id] = (((.[$container][$id] // {}) + {enabled: $enabled})
          | if has("sourceUrl") then . else . + {sourceUrl: $source_url} end);

      if has("states") then
        set_state("states"; "niri-overview-launcher"; $enable_niri)
        | set_state("states"; "screen-shot-and-record"; $enable_hypr)
        | set_state("states"; "special-workspaces"; $enable_hypr)
        | set_state("states"; "mangowc-layout-switcher"; $enable_mango)
      elif has("plugins") then
        set_state("plugins"; "niri-overview-launcher"; $enable_niri)
        | set_state("plugins"; "screen-shot-and-record"; $enable_hypr)
        | set_state("plugins"; "special-workspaces"; $enable_hypr)
        | set_state("plugins"; "mangowc-layout-switcher"; $enable_mango)
      else
        . + {states: {}}
        | set_state("states"; "niri-overview-launcher"; $enable_niri)
        | set_state("states"; "screen-shot-and-record"; $enable_hypr)
        | set_state("states"; "special-workspaces"; $enable_hypr)
        | set_state("states"; "mangowc-layout-switcher"; $enable_mango)
      end
    ' "${NOCTALIA_PLUGIN_STATE}" > "${tmp}"; then
    replace_file_if_changed "${tmp}" "${NOCTALIA_PLUGIN_STATE}" || true
  else
    rm -f "${tmp}"
  fi
}

apply_noctalia_settings_overrides() {
  local session_name="${1:-}"
  local tmp
  local enable_mango_widget="false"

  command -v jq >/dev/null 2>&1 || return 0
  ensure_noctalia_settings_state
  [[ -f "${NOCTALIA_SETTINGS_STATE}" ]] || return 0

  if [[ "${session_name}" == "mango" ]]; then
    enable_mango_widget="true"
  fi

  tmp="$(mktemp "${XDG_RUNTIME_DIR:-/tmp}/noctalia-settings.XXXXXX")"
  if jq \
    --argjson enable_mango_widget "${enable_mango_widget}" \
    --argjson mango_widget "${NOCTALIA_MANGO_LAYOUT_WIDGET_JSON}" \
    '
    def remove_widget($id):
      if .bar?.right?.widgets then
        .bar.right.widgets |= map(select((.id // "") != $id))
      else
        .
      end;

    def ensure_widget($widget):
      if $widget == null then
        .
      elif .bar?.right?.widgets then
        if any(.bar.right.widgets[]?; (.id // "") == ($widget.id // "")) then
          .
        else
          .bar.right.widgets += [$widget]
        end
      else
        .
      end;

    .general.enableBlurBehind = false
    | .wallpaper.overviewBlur = 0
    | remove_widget("plugin:mangowc-layout-switcher")
    | if $enable_mango_widget then ensure_widget($mango_widget) else . end
  ' "${NOCTALIA_SETTINGS_STATE}" > "${tmp}"; then
    replace_file_if_changed "${tmp}" "${NOCTALIA_SETTINGS_STATE}" || true
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

load_mango_env() {
  local helper="${SCRIPT_DIR}/mango-session-common.sh"
  [[ -r "$helper" ]] || helper="${SCRIPT_DIR}/mango-session-common"
  # shellcheck source=mango-session-common.sh
  source "$helper"
  mango_clear_foreign_session_env
  mango_load_session_env
  mango_normalize_session_paths
  mango_ensure_runtime_dir
  mango_ensure_session_identity
  export DESKTOP_SESSION="${DESKTOP_SESSION:-mango-uwsm}"
  mango_detect_wayland_display || true
}

session_backend="generic"

case "${XDG_CURRENT_DESKTOP:-${XDG_SESSION_DESKTOP:-${DESKTOP_SESSION:-}}}" in
  Hyprland|hyprland)
    load_hypr_env
    session_backend="hyprland"
    ;;
  niri|Niri)
    load_niri_env
    session_backend="niri"
    ;;
  mango|Mango|mangowm|MangoWM)
    load_mango_env
    session_backend="mango"
    ;;
esac

apply_noctalia_settings_overrides "${session_backend}"
apply_noctalia_plugin_overrides "${session_backend}"
prune_removed_noctalia_plugin_state

export XDG_ICON_THEME="${XDG_ICON_THEME:-${ICON_THEME:-kora}}"
export ICON_THEME="${ICON_THEME:-$XDG_ICON_THEME}"
export QT_ICON_THEME="${QT_ICON_THEME:-$XDG_ICON_THEME}"

if command -v gsettings >/dev/null 2>&1; then
  gsettings set org.gnome.desktop.interface icon-theme "$XDG_ICON_THEME" >/dev/null 2>&1 || true
fi

export XDG_DATA_DIRS="/usr/share:/usr/local/share:${HOME}/.local/share:${XDG_DATA_DIRS:-}"
export QT_QPA_PLATFORMTHEME="gtk3"

exec /usr/bin/qs -c noctalia-shell --no-duplicate
