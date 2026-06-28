#!/usr/bin/env bash
# ==============================================================================
# Script: delayed-portals
# Description: Starts xdg-desktop-portal services after a specific delay.
#              Targets the margo session (native margo-portal backend) with a
#              generic wlroots-based wayland fallback.
# Usage: delayed-portals [delay_seconds]
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
COMMON_HELPER="${SCRIPT_DIR}/wayland-session-common.sh"
MARGO_HELPER="${SCRIPT_DIR}/margo-session-common.sh"
[[ -r "${COMMON_HELPER}" ]] || COMMON_HELPER="${SCRIPT_DIR}/wayland-session-common"
[[ -r "${MARGO_HELPER}" ]] || MARGO_HELPER="${SCRIPT_DIR}/margo-session-common"

# shellcheck source=wayland-session-common.sh
source "${COMMON_HELPER}"
# shellcheck source=margo-session-common.sh
source "${MARGO_HELPER}"

DELAY="${1:-8}"
if ! [[ "$DELAY" =~ ^[0-9]+$ ]]; then
    DELAY=8
fi

sleep "$DELAY"

ensure_runtime_dir() {
    session_common_ensure_runtime_dir
}

detect_wayland_display() {
    session_common_detect_wayland_display
}

detect_desktop_name() {
    local desktop=""

    desktop="${XDG_CURRENT_DESKTOP:-${XDG_SESSION_DESKTOP:-${DESKTOP_SESSION:-}}}"
    desktop="${desktop%%:*}"

    if [[ -z "${desktop:-}" ]]; then
        desktop="wayland"
    fi

    printf '%s\n' "$desktop"
}

wait_for_session_ready() {
    local i

    for i in $(seq 1 600); do
        detect_wayland_display

        if [[ -n "${WAYLAND_DISPLAY:-}" ]] && [[ -S "${XDG_RUNTIME_DIR}/${WAYLAND_DISPLAY}" ]]; then
            return 0
        fi

        sleep 0.1
    done
    return 1
}

load_session_layer() {
    local desktop_name_lc="$1"

    case "$desktop_name_lc" in
        margo)
            margo_load_session_env
            ;;
    esac

    session_common_normalize_session_paths
}

sync_env() {
    local desktop_name=""
    local desktop_name_lc=""
    desktop_name="$(detect_desktop_name)"
    desktop_name_lc="$(printf '%s' "$desktop_name" | tr '[:upper:]' '[:lower:]')"

    load_session_layer "$desktop_name_lc"

    export XDG_CURRENT_DESKTOP="${XDG_CURRENT_DESKTOP:-$desktop_name}"
    export XDG_SESSION_TYPE="${XDG_SESSION_TYPE:-wayland}"
    export XDG_SESSION_DESKTOP="${XDG_SESSION_DESKTOP:-$desktop_name}"
    export DESKTOP_SESSION="${DESKTOP_SESSION:-$desktop_name}"

    local vars=(
        WAYLAND_DISPLAY
        DISPLAY
        XDG_CURRENT_DESKTOP
        XDG_SESSION_TYPE
        XDG_SESSION_DESKTOP
        DESKTOP_SESSION
        XDG_DATA_DIRS
        XDG_CONFIG_DIRS
        GTK_USE_PORTAL
        BROWSER
        PATH
    )

    if command -v systemctl >/dev/null 2>&1; then
        systemctl --user import-environment "${vars[@]}" 2>/dev/null || true

        local set_args=(
            "XDG_CURRENT_DESKTOP=${XDG_CURRENT_DESKTOP}"
            "XDG_SESSION_TYPE=${XDG_SESSION_TYPE}"
            "XDG_SESSION_DESKTOP=${XDG_SESSION_DESKTOP}"
            "DESKTOP_SESSION=${DESKTOP_SESSION}"
        )
        [[ -n "${WAYLAND_DISPLAY:-}" ]] && set_args+=("WAYLAND_DISPLAY=${WAYLAND_DISPLAY}")
        [[ -n "${DISPLAY:-}" ]] && set_args+=("DISPLAY=${DISPLAY}")
        systemctl --user set-environment "${set_args[@]}" 2>/dev/null || true
    fi

    if command -v dbus-update-activation-environment >/dev/null 2>&1; then
        dbus-update-activation-environment --systemd "${vars[@]}" >/dev/null 2>&1 \
            || dbus-update-activation-environment --systemd --all >/dev/null 2>&1 \
            || true
    fi
}

portal_config_path() {
    local config_home desktop desktop_name desktop_cfg default_cfg
    config_home="${XDG_CONFIG_HOME:-$HOME/.config}"
    desktop="${XDG_CURRENT_DESKTOP:-$(detect_desktop_name)}"
    desktop_name="${desktop%%:*}"
    desktop_name="$(printf '%s' "$desktop_name" | tr '[:upper:]' '[:lower:]')"

    desktop_cfg="${config_home}/xdg-desktop-portal/${desktop_name}-portals.conf"
    default_cfg="${config_home}/xdg-desktop-portal/portals.conf"

    if [[ -f "$desktop_cfg" ]]; then
        printf '%s\n' "$desktop_cfg"
        return 0
    fi

    if [[ -f "$default_cfg" ]]; then
        printf '%s\n' "$default_cfg"
        return 0
    fi

    return 1
}

# Map a portal backend keyword to its systemd user unit. margo ships its native
# backend as margo-portal.service rather than the xdg-desktop-portal-margo.service
# the generic naming scheme would imply.
portal_backend_service() {
    case "$1" in
        margo) printf '%s\n' "margo-portal.service" ;;
        *)     printf '%s\n' "xdg-desktop-portal-$1.service" ;;
    esac
}

collect_portal_backends() {
    local config_path="$1"

    # GTK should always remain available for common dialogs.
    printf '%s\n' "gtk"

    awk -F'=' '
      /^[[:space:]]*(default|org\.freedesktop\.impl\.portal\.(ScreenCast|Screenshot|RemoteDesktop|FileChooser|OpenURI|Settings|AppChooser|Notification|GlobalShortcuts|Inhibit|Email))[[:space:]]*=/ {
        value = $2
        sub(/[[:space:]]*#.*/, "", value)
        gsub(/[[:space:]]/, "", value)
        count = split(value, backends, /;/)
        for (i = 1; i <= count; i++) {
          backend = tolower(backends[i])
          if (backend == "gtk" || backend == "margo" || backend == "wlr") {
            print backend
          }
        }
      }
    ' "$config_path"

    if ! awk -F'=' '
      /^[[:space:]]*org\.freedesktop\.impl\.portal\.(ScreenCast|Screenshot|RemoteDesktop)[[:space:]]*=/ { found = 1 }
      END { exit(found ? 0 : 1) }
    ' "$config_path"; then
        # No screen-capture backend pinned (generic wayland fallback).
        printf '%s\n' "wlr"
    fi
}

if command -v systemctl >/dev/null 2>&1; then
    ensure_runtime_dir
    if ! wait_for_session_ready; then
        # Session wasn't fully ready in time; avoid restarting portals with
        # an incomplete environment (this can leave backends misconfigured).
        exit 0
    fi
    sync_env

    backends_stream=$'gtk\nwlr'
    if cfg_path="$(portal_config_path)"; then
        backends_stream="$(collect_portal_backends "$cfg_path")"
    fi

    declare -A restarted_backends=()
    while IFS= read -r backend; do
        [[ -n "$backend" ]] || continue
        [[ -n "${restarted_backends[$backend]:-}" ]] && continue
        restarted_backends["$backend"]=1
        backend_svc="$(portal_backend_service "$backend")"
        systemctl --user unmask "$backend_svc" 2>/dev/null || true
        systemctl --user restart "$backend_svc" 2>/dev/null || true
    done <<< "$backends_stream"

    # Keep backend selection strict:
    # - selected backends are unmasked + restarted
    # - competing screen-capture backends that were not selected are stopped
    #   + masked so they cannot shadow margo's native backend. margo is
    #   gnome-portal-free by design (see margo-portals.conf).
    for backend in gnome wlr; do
        if [[ -n "${restarted_backends[$backend]:-}" ]]; then
            continue
        fi
        systemctl --user stop "xdg-desktop-portal-${backend}.service" 2>/dev/null || true
        systemctl --user mask "xdg-desktop-portal-${backend}.service" 2>/dev/null || true
    done

    # Restart portal frontend after backend refresh.
    systemctl --user restart xdg-desktop-portal.service 2>/dev/null || true
fi
