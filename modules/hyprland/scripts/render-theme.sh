#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
MODULE_DIR="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
MANIFEST="${MODULE_DIR}/theme/theme.env"
ENV_OUT="${MODULE_DIR}/dotfiles/environment.d/10-hyprland.conf"
THEME_OUT="${MODULE_DIR}/dotfiles/hypr/conf.d/20-theme.conf"

usage() {
  cat <<'EOF'
Usage: render-theme.sh [--check]

Without arguments, regenerates the derived Hyprland theme files.
With --check, verifies that generated files match theme/theme.env.
EOF
}

mode="write"
case "${1:-}" in
  ""|--write)
    ;;
  --check)
    mode="check"
    ;;
  -h|--help)
    usage
    exit 0
    ;;
  *)
    usage >&2
    exit 2
    ;;
esac

# shellcheck source=/dev/null
source "${MANIFEST}"

manifest_checksum="$(sha256sum "${MANIFEST}" | awk '{print $1}')"
tmp_env="$(mktemp)"
tmp_theme="$(mktemp)"

cleanup() {
  rm -f "${tmp_env}" "${tmp_theme}"
}
trap cleanup EXIT

: "${CATPPUCCIN_FLAVOR:=mocha}"
: "${CATPPUCCIN_ACCENT:=mauve}"
: "${GTK_THEME:=catppuccin-mocha-mauve-standard+default}"
: "${XCURSOR_THEME:=capitaine-cursors}"
: "${XCURSOR_SIZE:=24}"
: "${HYPRCURSOR_THEME:=${XCURSOR_THEME}}"
: "${HYPRCURSOR_SIZE:=${XCURSOR_SIZE}}"
: "${THEME_HIGHLIGHT_HEX:=00bcd4}"
: "${THEME_BORDER_SIZE:=3}"
: "${THEME_ROUNDING:=8}"
: "${THEME_FLOATING_ROUNDING:=10}"

if [[ "${CATPPUCCIN_FLAVOR}" != "mocha" ]]; then
  printf 'Unsupported CATPPUCCIN_FLAVOR: %s\n' "${CATPPUCCIN_FLAVOR}" >&2
  exit 1
fi

declare -A palette=(
  [rosewater]=f5e0dc
  [flamingo]=f2cdcd
  [pink]=f5c2e7
  [mauve]=cba6f7
  [red]=f38ba8
  [maroon]=eba0ac
  [peach]=fab387
  [yellow]=f9e2af
  [green]=a6e3a1
  [teal]=94e2d5
  [sky]=89dceb
  [sapphire]=74c7ec
  [blue]=89b4fa
  [lavender]=b4befe
  [text]=cdd6f4
  [subtext1]=bac2de
  [subtext0]=a6adc8
  [overlay2]=9399b2
  [overlay1]=7f849c
  [overlay0]=6c7086
  [surface2]=585b70
  [surface1]=45475a
  [surface0]=313244
  [base]=1e1e2e
  [mantle]=181825
  [crust]=11111b
)

accent_hex="${palette[${CATPPUCCIN_ACCENT}]:-}"
if [[ -z "${accent_hex}" ]]; then
  printf 'Unsupported CATPPUCCIN_ACCENT: %s\n' "${CATPPUCCIN_ACCENT}" >&2
  exit 1
fi

path_core='/usr/local/bin:/usr/bin:/bin:/usr/local/sbin:${HOME}/.local/share/flatpak/exports/bin:/var/lib/flatpak/exports/bin:/usr/lib/jvm/default/bin:/usr/bin/site_perl:/usr/bin/vendor_perl:/usr/bin/core_perl'
path_user='${HOME}/.local/share/zinit/polaris/bin:${HOME}/.local/bin:${HOME}/bin:${HOME}/.iptv/bin:${HOME}/.local/share/go/bin'
path_combined='${HOME}/.local/share/zinit/polaris/bin:${HOME}/.local/bin:${HOME}/bin:${HOME}/.iptv/bin:/usr/local/bin:/usr/bin:/bin:/usr/local/sbin:${HOME}/.local/share/flatpak/exports/bin:/var/lib/flatpak/exports/bin:/usr/lib/jvm/default/bin:/usr/bin/site_perl:/usr/bin/vendor_perl:/usr/bin/core_perl:${HOME}/.local/share/go/bin'

cat >"${tmp_env}" <<EOF
# Generated from modules/hyprland/theme/theme.env.
# Update the manifest and rerun modules/hyprland/scripts/render-theme.sh.
# Source checksum: ${manifest_checksum}

# Canonical Hyprland session layer.
# UWSM/session wrappers own DESKTOP_SESSION and XDG_SESSION_DESKTOP. This file
# provides the Hyprland-specific environment that should win inside the
# compositor session.

XDG_CURRENT_DESKTOP=Hyprland
XDG_SESSION_TYPE=wayland
PATH_CORE=${path_core}
PATH_USER=${path_user}
PATH=${path_combined}
XDG_DATA_DIRS=\${HOME}/.local/share/flatpak/exports/share:/var/lib/flatpak/exports/share:/usr/local/share:/usr/share

BROWSER=start-helium-kenp
EDITOR=nvim
VISUAL=nvim
TERMINAL=kitty
HYPR_SYNC_GNOME_APPEARANCE=1

HYPRLAND_LOG_WLR=1
HYPRLAND_NO_RT=1
HYPRLAND_NO_SD_NOTIFY=1
HYPRLAND_NO_WATCHDOG_WARNING=1

XCURSOR_THEME=${XCURSOR_THEME}
XCURSOR_SIZE=${XCURSOR_SIZE}
HYPRCURSOR_THEME=${HYPRCURSOR_THEME}
HYPRCURSOR_SIZE=${HYPRCURSOR_SIZE}
FONTCONFIG_FILE=/etc/fonts/fonts.conf
LIBVA_DRIVER_NAME=iHD

CATPPUCCIN_FLAVOR=${CATPPUCCIN_FLAVOR}
CATPPUCCIN_ACCENT=${CATPPUCCIN_ACCENT}
EOF

cat >"${tmp_theme}" <<EOF
# Generated from modules/hyprland/theme/theme.env.
# Update the manifest and rerun modules/hyprland/scripts/render-theme.sh.
# Source checksum: ${manifest_checksum}

# Theme palette and visual assignments

\$gtkTheme = ${GTK_THEME}
\$catppuccinFlavor = ${CATPPUCCIN_FLAVOR}
\$catppuccinAccent = ${CATPPUCCIN_ACCENT}

\$rosewater = rgb(${palette[rosewater]})
\$rosewaterAlpha = ${palette[rosewater]}

\$flamingo = rgb(${palette[flamingo]})
\$flamingoAlpha = ${palette[flamingo]}

\$pink = rgb(${palette[pink]})
\$pinkAlpha = ${palette[pink]}

\$mauve = rgb(${palette[mauve]})
\$mauveAlpha = ${palette[mauve]}

\$red = rgb(${palette[red]})
\$redAlpha = ${palette[red]}

\$maroon = rgb(${palette[maroon]})
\$maroonAlpha = ${palette[maroon]}

\$peach = rgb(${palette[peach]})
\$peachAlpha = ${palette[peach]}

\$yellow = rgb(${palette[yellow]})
\$yellowAlpha = ${palette[yellow]}

\$green = rgb(${palette[green]})
\$greenAlpha = ${palette[green]}

\$teal = rgb(${palette[teal]})
\$tealAlpha = ${palette[teal]}

\$sky = rgb(${palette[sky]})
\$skyAlpha = ${palette[sky]}

\$sapphire = rgb(${palette[sapphire]})
\$sapphireAlpha = ${palette[sapphire]}

\$blue = rgb(${palette[blue]})
\$blueAlpha = ${palette[blue]}

\$lavender = rgb(${palette[lavender]})
\$lavenderAlpha = ${palette[lavender]}

\$text = rgb(${palette[text]})
\$textAlpha = ${palette[text]}

\$subtext1 = rgb(${palette[subtext1]})
\$subtext1Alpha = ${palette[subtext1]}

\$subtext0 = rgb(${palette[subtext0]})
\$subtext0Alpha = ${palette[subtext0]}

\$overlay2 = rgb(${palette[overlay2]})
\$overlay2Alpha = ${palette[overlay2]}

\$overlay1 = rgb(${palette[overlay1]})
\$overlay1Alpha = ${palette[overlay1]}

\$overlay0 = rgb(${palette[overlay0]})
\$overlay0Alpha = ${palette[overlay0]}

\$surface2 = rgb(${palette[surface2]})
\$surface2Alpha = ${palette[surface2]}

\$surface1 = rgb(${palette[surface1]})
\$surface1Alpha = ${palette[surface1]}

\$surface0 = rgb(${palette[surface0]})
\$surface0Alpha = ${palette[surface0]}

\$base = rgb(${palette[base]})
\$baseAlpha = ${palette[base]}

\$mantle = rgb(${palette[mantle]})
\$mantleAlpha = ${palette[mantle]}

\$crust = rgb(${palette[crust]})
\$crustAlpha = ${palette[crust]}

\$accent = rgb(${accent_hex})
\$accentAlpha = ${accent_hex}
\$highlight = rgb(${THEME_HIGHLIGHT_HEX})
\$highlightAlpha = ${THEME_HIGHLIGHT_HEX}
\$themeBorderSize = ${THEME_BORDER_SIZE}
\$themeRounding = ${THEME_ROUNDING}
\$themeFloatingRounding = ${THEME_FLOATING_ROUNDING}

general {
  border_size=\$themeBorderSize
  col.active_border=rgba(\$accentAlphaff)
  col.inactive_border=rgba(\$baseAlphaff)
}

decoration {
  blur {
    enabled=true
    ignore_opacity=true
    new_optimizations=true
    passes=2
    popups=true
    popups_ignorealpha=0.2
    size=9
    special=false
    vibrancy=0.155
    vibrancy_darkness=0.0
    xray=true
  }

  shadow {
    color=0x66000000
    enabled=true
    ignore_window=true
    offset=0 4
    range=27
    render_power=4
    scale=0.975
  }

  active_opacity=1.0
  dim_inactive=true
  dim_strength=0.12
  fullscreen_opacity=1.0
  inactive_opacity=0.88
  rounding=\$themeRounding
}

group {
  groupbar {
    col.active=rgba(\$blueAlphaed)
    col.inactive=rgba(\$overlay0Alphaa8)
    col.locked_active=rgba(\$accentAlphaed)
    col.locked_inactive=rgba(\$surface1Alphaa8)
    font_size=10
    gradients=false
    render_titles=false
  }
  col.border_active=rgba(\$accentAlphaff)
  col.border_inactive=rgba(\$baseAlphaff)
  col.border_locked_active=rgba(\$accentAlphaff)
  col.border_locked_inactive=rgba(\$baseAlphaff)
}

misc {
  background_color=rgba(\$baseAlphaff)
}

# Workspace chrome exceptions
workspace=f[1], gapsout:0, gapsin:0, rounding:0, shadow:0
workspace=special:dropdown, gapsout:0, gapsin:0, bordersize:0, rounding:0, shadow:0
workspace=special:scratchpad, gapsout:0, gapsin:0, bordersize:0, rounding:0, shadow:0
EOF

verify_output() {
  local generated="$1"
  local current="$2"
  local label="$3"

  if [[ ! -f "$current" ]]; then
    printf 'Missing generated file: %s\n' "$label" >&2
    return 1
  fi

  if ! cmp -s "$generated" "$current"; then
    printf 'Stale generated file detected: %s\n' "$label" >&2
    return 1
  fi
}

write_if_changed() {
  local generated="$1"
  local current="$2"
  local current_mode=''

  if [[ -e "$current" ]]; then
    current_mode="$(stat -c '%a' "$current")"
  fi

  if cmp -s "$generated" "$current" 2>/dev/null &&
    [[ -O "$current" ]] &&
    [[ "$current_mode" == "644" ]]; then
    return 0
  fi

  install -m 644 "$generated" "$current"
}

if [[ "$mode" == "check" ]]; then
  verify_output "$tmp_env" "$ENV_OUT" "$ENV_OUT"
  verify_output "$tmp_theme" "$THEME_OUT" "$THEME_OUT"
  exit 0
fi

write_if_changed "$tmp_env" "$ENV_OUT"
write_if_changed "$tmp_theme" "$THEME_OUT"
