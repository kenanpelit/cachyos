#!/usr/bin/env bash
set -e

# --- Core GNOME Settings ---
# Workspaces
gsettings set org.gnome.desktop.wm.preferences num-workspaces 9
gsettings set org.gnome.desktop.wm.preferences workspace-names "['1', '2', '3', '4', '5', '6', '7', '8', '9']"

# Interface
gsettings set org.gnome.desktop.interface show-battery-percentage true
gsettings set org.gnome.desktop.interface clock-show-weekday true
gsettings set org.gnome.desktop.interface clock-show-date true
gsettings set org.gnome.desktop.interface accent-color 'purple'
# Make animations snappy like Niri
gsettings set org.gnome.desktop.interface enable-animations false

# --- Niri-like Experience (PaperWM & Just Perfection) ---

# Disable GNOME Super Key default (Overview)
gsettings set org.gnome.mutter overlay-key ''

# Just Perfection (Minimalist Niri vibe)
gsettings set org.gnome.shell.extensions.just-perfection activities-button false
gsettings set org.gnome.shell.extensions.just-perfection show-apps-button false
gsettings set org.gnome.shell.extensions.just-perfection dash false
gsettings set org.gnome.shell.extensions.just-perfection workspace-popup false
gsettings set org.gnome.shell.extensions.just-perfection window-preview-caption false

# PaperWM (Scrollable Tiling)
gsettings set org.gnome.shell.extensions.paperwm window-gap 8
gsettings set org.gnome.shell.extensions.paperwm vertical-margin 8
gsettings set org.gnome.shell.extensions.paperwm vertical-margin-bottom 8
gsettings set org.gnome.shell.extensions.paperwm horizontal-margin 8
gsettings set org.gnome.shell.extensions.paperwm show-workspace-indicator false

# Enable Extensions (if not already enabled)
gnome-extensions enable paperwm@paperwm.github.com || true
gnome-extensions enable just-perfection-desktop@just-perfection || true

# --- Keybindings ---

# Window Manager Keybindings
# Close window
gsettings set org.gnome.desktop.wm.keybindings close "['<Super>q']"
# Fullscreen
gsettings set org.gnome.desktop.wm.keybindings toggle-fullscreen "['<Super>f']"

# Workspaces (Switch)
gsettings set org.gnome.desktop.wm.keybindings switch-to-workspace-1 "['<Super>1']"
gsettings set org.gnome.desktop.wm.keybindings switch-to-workspace-2 "['<Super>2']"
gsettings set org.gnome.desktop.wm.keybindings switch-to-workspace-3 "['<Super>3']"
gsettings set org.gnome.desktop.wm.keybindings switch-to-workspace-4 "['<Super>4']"
gsettings set org.gnome.desktop.wm.keybindings switch-to-workspace-5 "['<Super>5']"
gsettings set org.gnome.desktop.wm.keybindings switch-to-workspace-6 "['<Super>6']"
gsettings set org.gnome.desktop.wm.keybindings switch-to-workspace-7 "['<Super>7']"
gsettings set org.gnome.desktop.wm.keybindings switch-to-workspace-8 "['<Super>8']"
gsettings set org.gnome.desktop.wm.keybindings switch-to-workspace-9 "['<Super>9']"

# Workspaces (Move Window)
gsettings set org.gnome.desktop.wm.keybindings move-to-workspace-1 "['<Super><Shift>1']"
gsettings set org.gnome.desktop.wm.keybindings move-to-workspace-2 "['<Super><Shift>2']"
gsettings set org.gnome.desktop.wm.keybindings move-to-workspace-3 "['<Super><Shift>3']"
gsettings set org.gnome.desktop.wm.keybindings move-to-workspace-4 "['<Super><Shift>4']"
gsettings set org.gnome.desktop.wm.keybindings move-to-workspace-5 "['<Super><Shift>5']"
gsettings set org.gnome.desktop.wm.keybindings move-to-workspace-6 "['<Super><Shift>6']"
gsettings set org.gnome.desktop.wm.keybindings move-to-workspace-7 "['<Super><Shift>7']"
gsettings set org.gnome.desktop.wm.keybindings move-to-workspace-8 "['<Super><Shift>8']"
gsettings set org.gnome.desktop.wm.keybindings move-to-workspace-9 "['<Super><Shift>9']"

# PaperWM Niri-like Window Focus (Vim keys & Arrows)
gsettings set org.gnome.shell.extensions.paperwm.keybindings switch-left "['<Super>Left', '<Super>h']"
gsettings set org.gnome.shell.extensions.paperwm.keybindings switch-right "['<Super>Right', '<Super>l']"
gsettings set org.gnome.shell.extensions.paperwm.keybindings switch-up "['<Super>Up', '<Super>k']"
gsettings set org.gnome.shell.extensions.paperwm.keybindings switch-down "['<Super>Down', '<Super>j']"

# PaperWM Niri-like Window Move (Vim keys & Arrows)
gsettings set org.gnome.shell.extensions.paperwm.keybindings move-left "['<Super><Shift>Left', '<Super><Shift>h']"
gsettings set org.gnome.shell.extensions.paperwm.keybindings move-right "['<Super><Shift>Right', '<Super><Shift>l']"
gsettings set org.gnome.shell.extensions.paperwm.keybindings move-up "['<Super><Shift>Up', '<Super><Shift>k']"
gsettings set org.gnome.shell.extensions.paperwm.keybindings move-down "['<Super><Shift>Down', '<Super><Shift>j']"

# Shell Keybindings
gsettings set org.gnome.shell.keybindings toggle-application-view "[]" # Disabled, Walker will be used
gsettings set org.gnome.shell.keybindings toggle-message-tray "['<Super>n']"

# Custom Keybinding: Walker as Launcher
gsettings set org.gnome.settings-daemon.plugins.media-keys custom-keybindings "['/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom0/', '/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom1/']"

gsettings set org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom0/ name 'Walker'
gsettings set org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom0/ command 'walker'
gsettings set org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom0/ binding '<Super>space'

# Custom Keybinding: Kitty Terminal (Niri default terminal style)
gsettings set org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom1/ name 'Terminal'
gsettings set org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom1/ command 'kitty'
gsettings set org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom1/ binding '<Super>Return'


# Mouse/Touchpad
gsettings set org.gnome.desktop.peripherals.touchpad tap-to-click true
gsettings set org.gnome.desktop.peripherals.touchpad natural-scroll false

echo "GNOME Niri-style settings applied successfully!"
