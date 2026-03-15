#!/usr/bin/env bash
set -euo pipefail

# --- User Config Setup ---
REAL_USER="${SUDO_USER:-$(whoami)}"
USER_HOME="$(getent passwd "$REAL_USER" | cut -d: -f6 2>/dev/null || true)"
if [ -z "${USER_HOME:-}" ]; then
  USER_HOME="$(eval echo "~$REAL_USER")"
fi

HYPR_DIR="$USER_HOME/.config/hypr"
DMS_DIR="$HYPR_DIR/dms"
CONF_D_DIR="$HYPR_DIR/conf.d"
BIN_DIR="$USER_HOME/.local/bin"

USER_GROUP=""
if [ "$(id -u)" -eq 0 ]; then
  USER_GROUP="$(id -gn "$REAL_USER" 2>/dev/null || true)"
fi

if [ -L "$CONF_D_DIR" ]; then
  rm -f "$CONF_D_DIR"
fi

if [ "$(id -u)" -eq 0 ] && [ -n "$USER_GROUP" ]; then
  install -d -m0755 -o "$REAL_USER" -g "$USER_GROUP" "$HYPR_DIR" "$DMS_DIR" "$CONF_D_DIR" "$BIN_DIR"
  chown "$REAL_USER:$USER_GROUP" "$HYPR_DIR" "$DMS_DIR" "$CONF_D_DIR" "$BIN_DIR" 2>/dev/null || true
else
  mkdir -p "$DMS_DIR" "$CONF_D_DIR" "$BIN_DIR"
fi

for f in 90-outputs-local.conf 91-cursor-local.conf 92-monitors-local.conf; do
  path="$CONF_D_DIR/$f"
  if [ -L "$path" ]; then
    rm -f "$path"
  fi
  if [ ! -e "$path" ]; then
    if [ "$f" = "92-monitors-local.conf" ]; then
      cat >"$path" <<'EOF'
# Host-local monitor and workspace routing.
monitor=desc:Dell Inc. DELL UP2716D KRXTR88N909L,2560x1440@59,0x0,1
monitor=desc:Chimei Innolux Corporation 0x143F,1920x1200@60,320x1440,1
monitor=,preferred,auto,1
workspace=1, monitor:desc:Dell Inc. DELL UP2716D KRXTR88N909L, default:true
workspace=2, monitor:desc:Dell Inc. DELL UP2716D KRXTR88N909L
workspace=3, monitor:desc:Dell Inc. DELL UP2716D KRXTR88N909L
workspace=4, monitor:desc:Dell Inc. DELL UP2716D KRXTR88N909L
workspace=5, monitor:desc:Dell Inc. DELL UP2716D KRXTR88N909L
workspace=6, monitor:desc:Dell Inc. DELL UP2716D KRXTR88N909L
workspace=7, monitor:desc:Chimei Innolux Corporation 0x143F, default:true
workspace=8, monitor:desc:Chimei Innolux Corporation 0x143F
workspace=9, monitor:desc:Chimei Innolux Corporation 0x143F
EOF
    elif [ "$(id -u)" -eq 0 ] && [ -n "$USER_GROUP" ]; then
      install -m0644 -o "$REAL_USER" -g "$USER_GROUP" /dev/null "$path"
    else
      : > "$path"
    fi
  fi
  chmod 0644 "$path" || true
  if [ "$(id -u)" -eq 0 ] && [ -n "$USER_GROUP" ]; then
    chown "$REAL_USER:$USER_GROUP" "$path" 2>/dev/null || true
  fi
done

# --- System-wide Session Entry ---
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
DOTFILES_DIR="$SCRIPT_DIR/../dotfiles"
# Desktop entry still needs to be in /usr/share/wayland-sessions to be seen by the greeter.
echo "Checking system-wide Hyprland session entry..."
if [ -w "/usr/share/wayland-sessions" ] || [ -n "${SUDO_USER:-}" ]; then
    mkdir -p "/usr/share/wayland-sessions"
    cp "$DOTFILES_DIR/hyprland-optimized.desktop" "/usr/share/wayland-sessions/hyprland-optimized.desktop"
    chmod 644 "/usr/share/wayland-sessions/hyprland-optimized.desktop"
else
    echo "  ! Skipping desktop entry install: No write access to /usr/share/wayland-sessions (run 'dcli sync' with sudo)"
fi
