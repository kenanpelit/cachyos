#!/usr/bin/env bash
# ==============================================================================
# Script: delayed-portals
# Description: Starts xdg-desktop-portal services after a specific delay.
# Usage: delayed-portals [delay_seconds]
# ==============================================================================

set -euo pipefail

DELAY="${1:-8}"
if ! [[ "$DELAY" =~ ^[0-9]+$ ]]; then
    DELAY=8
fi

sleep "$DELAY"

ensure_runtime_dir() {
    if [[ -z "${XDG_RUNTIME_DIR:-}" ]]; then
        XDG_RUNTIME_DIR="/run/user/$(id -u)"
        export XDG_RUNTIME_DIR
    fi
}

detect_wayland_display() {
    if [[ -n "${WAYLAND_DISPLAY:-}" ]]; then
        return 0
    fi
    [[ -n "${XDG_RUNTIME_DIR:-}" ]] || return 0
    local sock
    for sock in "${XDG_RUNTIME_DIR}"/wayland-*; do
        [[ -S "$sock" ]] || continue
        WAYLAND_DISPLAY="$(basename "$sock")"
        export WAYLAND_DISPLAY
        return 0
    done
}

detect_niri_socket() {
    [[ -n "${XDG_RUNTIME_DIR:-}" ]] || return 0
    [[ -n "${WAYLAND_DISPLAY:-}" ]] || return 0
    [[ -n "${NIRI_SOCKET:-}" ]] && return 0

    shopt -s nullglob
    local sock
    for sock in "${XDG_RUNTIME_DIR}/niri.${WAYLAND_DISPLAY}."*.sock; do
        [[ -S "$sock" ]] || continue
        NIRI_SOCKET="$sock"
        export NIRI_SOCKET
        break
    done
    shopt -u nullglob
}

wait_for_session_ready() {
    local i
    for i in $(seq 1 600); do
        detect_wayland_display
        detect_niri_socket

        if [[ -n "${WAYLAND_DISPLAY:-}" ]] && [[ -S "${XDG_RUNTIME_DIR}/${WAYLAND_DISPLAY}" ]]; then
            if [[ -n "${NIRI_SOCKET:-}" ]] && [[ -S "${NIRI_SOCKET}" ]]; then
                if command -v niri >/dev/null 2>&1; then
                    if NIRI_SOCKET="${NIRI_SOCKET}" niri msg version >/dev/null 2>&1; then
                        return 0
                    fi
                else
                    return 0
                fi
            fi
        fi
        sleep 0.1
    done
    return 1
}

sync_env() {
    export XDG_CURRENT_DESKTOP="${XDG_CURRENT_DESKTOP:-niri}"
    export XDG_SESSION_TYPE="${XDG_SESSION_TYPE:-wayland}"
    export XDG_SESSION_DESKTOP="${XDG_SESSION_DESKTOP:-niri}"
    export DESKTOP_SESSION="${DESKTOP_SESSION:-niri}"

    local vars=(
        WAYLAND_DISPLAY
        DISPLAY
        NIRI_SOCKET
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
        [[ -n "${NIRI_SOCKET:-}" ]] && set_args+=("NIRI_SOCKET=${NIRI_SOCKET}")
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
    desktop="${XDG_CURRENT_DESKTOP:-niri}"
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

collect_portal_backends() {
    local config_path="$1"

    # Keep GTK portal available for file chooser / URI / settings dialogs.
    printf '%s\n' "gtk"

    awk -F'=' '
      /^[[:space:]]*org\.freedesktop\.impl\.portal\.(ScreenCast|Screenshot|RemoteDesktop|FileChooser|OpenURI|Settings)[[:space:]]*=/ {
        value = $2
        sub(/[[:space:]]*#.*/, "", value)
        gsub(/[[:space:]]/, "", value)
        count = split(value, backends, /;/)
        for (i = 1; i <= count; i++) {
          if (backends[i] != "") {
            print tolower(backends[i])
          }
        }
      }
    ' "$config_path"

    if ! awk -F'=' '
      /^[[:space:]]*org\.freedesktop\.impl\.portal\.(ScreenCast|Screenshot|RemoteDesktop)[[:space:]]*=/ { found = 1 }
      END { exit(found ? 0 : 1) }
    ' "$config_path"; then
        # Safe fallback for Niri/wlroots-like sessions.
        printf '%s\n' "wlr"
    fi
}

if command -v systemctl >/dev/null 2>&1; then
    ensure_runtime_dir
    if ! wait_for_session_ready; then
        # Session wasn't fully ready in time; avoid restarting portals with
        # incomplete environment (this can leave gnome backend in settings-only mode).
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
        systemctl --user restart "xdg-desktop-portal-${backend}.service" 2>/dev/null || true
    done <<< "$backends_stream"

    # Keep compositor backend selection strict:
    # - selected backends are unmasked + restarted
    # - non-selected backends are stopped + masked
    # This avoids stale backends (e.g. wlr) shadowing expected behavior/logging.
    for backend in gnome wlr hyprland kde; do
        if [[ -n "${restarted_backends[$backend]:-}" ]]; then
            systemctl --user unmask "xdg-desktop-portal-${backend}.service" 2>/dev/null || true
            continue
        fi
        systemctl --user stop "xdg-desktop-portal-${backend}.service" 2>/dev/null || true
        systemctl --user mask "xdg-desktop-portal-${backend}.service" 2>/dev/null || true
    done

    # Restart portal frontend after backend refresh.
    systemctl --user restart xdg-desktop-portal.service 2>/dev/null || true
fi
