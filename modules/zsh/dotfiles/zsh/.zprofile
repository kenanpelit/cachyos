# =============================================================================
# NixOS Multi-TTY Desktop Environment Auto-Start Configuration
# =============================================================================
# This profile handles ONLY TTY detection and session routing.
# All environment variables are set in their respective startup scripts.
# =============================================================================
# TTY Assignments:
#   TTY1: Display Manager - Session Selection
#   TTY2: Niri (via ~/.local/bin/niri-set tty)
#   TTY3: Hyprland (via ~/.local/bin/hypr-set tty)
#   TTY4: GNOME (via ~/.local/bin/gnome_tty)
#   TTY5: Ubuntu VM (Sway)
#   TTY6: Manual start helper
# =============================================================================

# Only run in login shell when no desktop is active
# CRITICAL: Also check if we're being called from a desktop session startup
# (gnome-session etc. may re-exec shell during startup)
if [[ $- == *l* ]] && [ -z "${WAYLAND_DISPLAY}" ] && [ -z "${DISPLAY}" ] && [[ "${XDG_VTNR}" =~ ^[1-6]$ ]] && [ -z "${NIRI_TTY_GUARD:-}" ] && [ -z "${GNOME_TTY_GUARD:-}" ]; then

    NIRI_SET="${HOME}/.local/bin/niri-set"
    HYPR_SET="${HOME}/.local/bin/hypr-set"
    GNOME_TTY="${HOME}/.local/bin/gnome_tty"

    # TTY1 special check: Don't interfere if session already active
    if [ "${XDG_VTNR}" = "1" ] && [ -n "${XDG_SESSION_TYPE}" ]; then
        return
    fi

    # CRITICAL FIX: Prevent re-running when called from desktop session startup
    # Desktop sessions (GNOME) may re-exec shell with login flag
    # Check if we're in a desktop session startup context
    # IMPORTANT: Only check for actual running sessions, not just env vars
    if pgrep -x "gnome-shell" >/dev/null 2>&1 || \
       [ -n "${GNOME_DESKTOP_SESSION_ID:-}" ] || \
       [ -n "${GNOME_SHELL_SESSION_MODE:-}" ]; then
        return
    fi
    
    # ==========================================================================
    # TTY1: Display Manager
    # ==========================================================================
    if [ "${XDG_VTNR}" = "1" ]; then
        echo "╔════════════════════════════════════════════════════════════╗"
        echo "║  TTY1: Display Manager                                     ║"
        echo "╚════════════════════════════════════════════════════════════╝"
        echo ""
        echo "Available Desktop Sessions:"
        echo "  • Niri    - Minimal Wayland compositor"
        echo "  • Hyprland - Dynamic tiling Wayland compositor"
        echo "  • GNOME    - Traditional GNOME desktop"
        echo ""
        echo "Manual Start Commands:"
        echo "  exec ${NIRI_SET} tty  - Start Niri with optimizations"
        echo "  exec ${HYPR_SET} tty  - Start Hyprland with optimizations"
        echo "  exec ${GNOME_TTY}     - Start GNOME with optimizations"
        echo ""
    
    # ==========================================================================
    # TTY2: Niri Wayland Compositor
    # ==========================================================================
    elif [ "${XDG_VTNR}" = "2" ]; then
        echo "╔════════════════════════════════════════════════════════════╗"
        echo "║  TTY2: Launching Niri via niri-set tty                     ║"
        echo "╚════════════════════════════════════════════════════════════╝"

        export XDG_SESSION_TYPE=wayland
        export XDG_RUNTIME_DIR="/run/user/$(id -u)"
        # NixOS'ta setuid sudo sadece /run/wrappers/bin içindedir.
        # /run/current-system/sw/bin/sudo setuid değildir ve şu hataya yol açar:
        #   sudo must be owned by uid 0 and have the setuid bit set
                export NIRI_TTY_GUARD=1

        if [ -x "${NIRI_SET}" ]; then
            echo "Starting Niri with optimized configuration..."
            exec "${NIRI_SET}" tty
        else
            echo "ERROR: niri-set not found: ${NIRI_SET}"
            echo "Falling back to direct Niri launch (not recommended)"
            sleep 3
            exec niri 2>&1 | tee /tmp/niri-tty2.log
        fi
    
    # ==========================================================================
    # TTY3: Hyprland Wayland Compositor
    # ==========================================================================
    elif [ "${XDG_VTNR}" = "3" ]; then
        echo "╔════════════════════════════════════════════════════════════╗"
        echo "║  TTY3: Launching Hyprland via hypr-set tty                 ║"
        echo "╚════════════════════════════════════════════════════════════╝"
        
        # Minimum required variables - rest configured in hyprland_tty
        export XDG_SESSION_TYPE=wayland
        export XDG_RUNTIME_DIR="/run/user/$(id -u)"
        
        # Check for hypr-set script
        if [ -x "${HYPR_SET}" ]; then
            echo "Starting Hyprland with optimized configuration..."
            exec "${HYPR_SET}" tty
        else
            echo "ERROR: hypr-set not found: ${HYPR_SET}"
            echo "Falling back to direct Hyprland launch (not recommended)"
            sleep 3
            exec Hyprland
        fi
    
    # ==========================================================================
    # TTY4: GNOME Desktop Environment
    # ==========================================================================
    elif [ "${XDG_VTNR}" = "4" ]; then
        echo "╔════════════════════════════════════════════════════════════╗"
        echo "║  TTY4: Launching GNOME via gnome_tty                       ║"
        echo "╚════════════════════════════════════════════════════════════╝"

        # CRITICAL: Only set XDG_RUNTIME_DIR - let gnome_tty handle everything else
        # Setting XDG_SESSION_TYPE, XDG_SESSION_DESKTOP etc here causes problems
        export XDG_RUNTIME_DIR="/run/user/$(id -u)"
        export GNOME_TTY_GUARD=1
        if [ -e "${XDG_RUNTIME_DIR}/gnome-tty4.guard" ]; then
            echo "GNOME zaten başlatılıyor (guard aktif), tekrar tetiklenmiyor."
            return
        fi
        export GNOME_TTY_GUARD_FILE="${XDG_RUNTIME_DIR}/gnome-tty4.guard"

        # Check for gnome_tty script
        if [ -x "${GNOME_TTY}" ]; then
            echo "Starting GNOME with optimized configuration..."
            exec "${GNOME_TTY}"
        else
            echo "ERROR: gnome_tty not found: ${GNOME_TTY}"
            echo "Falling back to direct GNOME launch (not recommended)"
            sleep 3

            # Fallback: Start GNOME with proper environment
            export XDG_SESSION_TYPE=wayland
            export SYSTEMD_OFFLINE=0

            # Start GNOME session directly (no dbus-run-session wrapper)
            exec gnome-session --session=gnome --no-reexec 2>&1 | tee /tmp/gnome-session-tty4.log
        fi
    
    # ==========================================================================
    # TTY5: Ubuntu VM in Sway
    # ==========================================================================
    elif [ "${XDG_VTNR}" = "5" ]; then
        echo "╔════════════════════════════════════════════════════════════╗"
        echo "║  TTY5: Starting Ubuntu VM in Sway                          ║"
        echo "╚════════════════════════════════════════════════════════════╝"
        
        # Clean environment
        unset XDG_CURRENT_DESKTOP XDG_SESSION_DESKTOP DESKTOP_SESSION
        
        # Sway environment settings
        export XDG_SESSION_TYPE=wayland
        export XDG_SESSION_DESKTOP=sway
        export XDG_CURRENT_DESKTOP=sway
        export DESKTOP_SESSION=sway
        export XDG_RUNTIME_DIR="/run/user/$(id -u)"
        
        # Add user bin to PATH for svmubuntu command
                
        echo "Environment: Sway compositor for Ubuntu VM"
        echo "VM Command: svmubuntu"
        
        # Check Sway config
        if [ -f ~/.config/sway/qemu_vmubuntu ]; then
            echo "Starting Sway with Ubuntu VM configuration..."
            exec sway -c ~/.config/sway/qemu_vmubuntu 2>&1 | tee /tmp/sway-tty5.log
        else
            echo "ERROR: Sway config not found: ~/.config/sway/qemu_vmubuntu"
            echo "Expected location: ~/.config/sway/qemu_vmubuntu"
            echo "Please verify the configuration file exists"
            sleep 5
            return
        fi
    
    # ==========================================================================
    # Other TTYs: Manual use information
    # ==========================================================================
    else
        echo "╔════════════════════════════════════════════════════════════╗"
        echo "║  TTY${XDG_VTNR}: No auto-start configured                ║"
        echo "╚════════════════════════════════════════════════════════════╝"
        echo ""
        echo "Available TTY Assignments:"
        echo "  TTY1: Display Manager (gdm)"
        echo "  TTY2: Niri (${NIRI_SET} tty)"
        echo "  TTY3: Hyprland (${HYPR_SET} tty)"
        echo "  TTY4: GNOME (${GNOME_TTY})"
        echo "  TTY5: Ubuntu VM (Sway)"
        echo "  TTY6: Manual start helper"
        echo ""
        echo "Manual Start Commands:"
        echo "  exec ${NIRI_SET} tty  - Niri with optimizations"
        echo "  exec ${HYPR_SET} tty  - Hyprland with optimizations"
        echo "  exec ${GNOME_TTY}     - GNOME with optimizations"
        echo "  exec sway            - Sway compositor"
        echo ""
    fi
    
fi
# Silent continue if not login shell or desktop already running
