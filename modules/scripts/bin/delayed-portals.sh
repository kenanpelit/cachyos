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

wait_for_wayland() {
    local i
    for i in $(seq 1 50); do
        detect_wayland_display
        if [[ -n "${WAYLAND_DISPLAY:-}" ]] && [[ -S "${XDG_RUNTIME_DIR}/${WAYLAND_DISPLAY}" ]]; then
            return 0
        fi
        sleep 0.1
    done
    return 0
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

if command -v systemctl >/dev/null 2>&1; then
    ensure_runtime_dir
    wait_for_wayland
    detect_niri_socket
    sync_env

    # Restart portals to ensure they pick up the fresh environment
    systemctl --user restart xdg-desktop-portal-gnome.service 2>/dev/null || true
    systemctl --user restart xdg-desktop-portal-gtk.service 2>/dev/null || true
    systemctl --user restart xdg-desktop-portal.service 2>/dev/null || true
fi
