#!/usr/bin/env bash
# ==============================================================================
# Script: gnome-settings.sh
# Description: Complete GNOME configuration script with Catppuccin Mocha theme.
# Usage: gnome-settings.sh
# ==============================================================================

set -euo pipefail

# Log dizinini oluştur
LOG_DIR="$HOME/.logs"
LOG_FILE="$LOG_DIR/gnome_settings_$(date +%Y%m%d_%H%M%S).log"
mkdir -p "$LOG_DIR"

# Debug mode'u aktif et ve log'a yönlendir
exec > >(tee -a "$LOG_FILE") 2>&1
set -x

echo "🚀 GNOME Complete Configuration başlatılıyor..."
echo "📝 Log dosyası: $LOG_FILE"
echo "🕐 Başlama zamanı: $(date)"

# Font ayarları
MAIN_FONT="Maple Mono NF"
EDITOR_FONT="Maple Mono NF"
TERMINAL_FONT="Maple Mono NF"
FONT_SIZE_SM="12"
FONT_SIZE_MD="13"
FONT_SIZE_XL="15"

# =============================================================================
# CATPPUCCIN MOCHA RENK PALETİ
# =============================================================================
MOCHA_BASE="#1e1e2e"
MOCHA_MANTLE="#181825"
MOCHA_CRUST="#11111b"
MOCHA_TEXT="#cdd6f4"
MOCHA_SUBTEXT1="#bac2de"
MOCHA_SUBTEXT0="#a6adc8"
MOCHA_OVERLAY2="#9399b2"
MOCHA_OVERLAY1="#7f849c"
MOCHA_OVERLAY0="#6c7086"
MOCHA_SURFACE2="#585b70"
MOCHA_SURFACE1="#45475a"
MOCHA_SURFACE0="#313244"
MOCHA_MAUVE="#cba6f7"
MOCHA_LAVENDER="#b4befe"
MOCHA_BLUE="#89b4fa"
MOCHA_SAPPHIRE="#74c7ec"
MOCHA_SKY="#89dceb"
MOCHA_TEAL="#94e2d5"
MOCHA_GREEN="#a6e3a1"
MOCHA_YELLOW="#f9e2af"
MOCHA_PEACH="#fab387"
MOCHA_MAROON="#eba0ac"
MOCHA_RED="#f38ba8"
MOCHA_PINK="#f5c2e7"
MOCHA_FLAMINGO="#f2cdcd"
MOCHA_ROSEWATER="#f5e0dc"
# Niri accent (used for border/focus parity across desktops)
NIRI_CYAN="#00BCD4"

echo "📝 Mevcut ayarları temizleniyor..."
# Sadece custom keybinding'leri temizle, diğerlerini koru
dconf reset -f /org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/

# =============================================================================
# TEXT EDITOR CONFIGURATION
# =============================================================================
echo "📄 Text Editor ayarları uygulanıyor..."

dconf write /org/gnome/TextEditor/custom-font "'$EDITOR_FONT $FONT_SIZE_XL'"
dconf write /org/gnome/TextEditor/highlight-current-line "true"
dconf write /org/gnome/TextEditor/indent-style "'space'"
dconf write /org/gnome/TextEditor/restore-session "false"
dconf write /org/gnome/TextEditor/show-grid "false"
dconf write /org/gnome/TextEditor/show-line-numbers "true"
dconf write /org/gnome/TextEditor/show-right-margin "false"
dconf write /org/gnome/TextEditor/style-scheme "'catppuccin-mocha'"
dconf write /org/gnome/TextEditor/style-variant "'dark'"
dconf write /org/gnome/TextEditor/tab-width "uint32 4"
dconf write /org/gnome/TextEditor/use-system-font "false"
dconf write /org/gnome/TextEditor/wrap-text "false"

# =============================================================================
# INTERFACE CONFIGURATION
# =============================================================================
echo "🎨 Interface ayarları uygulanıyor..."

dconf write /org/gnome/desktop/interface/font-name "'$MAIN_FONT $FONT_SIZE_SM'"
dconf write /org/gnome/desktop/interface/document-font-name "'$MAIN_FONT $FONT_SIZE_SM'"
dconf write /org/gnome/desktop/interface/monospace-font-name "'$TERMINAL_FONT $FONT_SIZE_SM'"
dconf write /org/gnome/desktop/interface/color-scheme "'prefer-dark'"
# Also set via gsettings (some setups read this more reliably than raw dconf writes)
command -v gsettings >/dev/null 2>&1 && gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark' || true
dconf write /org/gnome/desktop/interface/font-antialiasing "'grayscale'"
dconf write /org/gnome/desktop/interface/font-hinting "'slight'"
dconf write /org/gnome/desktop/interface/show-battery-percentage "true"
dconf write /org/gnome/desktop/interface/clock-show-weekday "true"
dconf write /org/gnome/desktop/interface/clock-show-date "true"
dconf write /org/gnome/desktop/interface/enable-animations "true"

# =============================================================================
# GTK THEME SETTINGS (Catppuccin Mocha)
# =============================================================================
echo "🎨 GTK tema ayarları (Catppuccin Mocha)..."

dconf write /org/gnome/desktop/interface/gtk-theme "'catppuccin-mocha-mauve-standard+default'"
dconf write /org/gnome/desktop/interface/icon-theme "'kora'"
dconf write /org/gnome/desktop/interface/cursor-theme "'catppuccin-mocha-dark-cursors'"
dconf write /org/gnome/desktop/interface/cursor-size "24"

# Shell tema
dconf write /org/gnome/shell/extensions/user-theme/name "'catppuccin-mocha-mauve-standard+default'"

# Accent color (GNOME 44+)
dconf write /org/gnome/desktop/interface/accent-color "'purple'"

# Window decorations
dconf write /org/gnome/desktop/wm/preferences/theme "'catppuccin-mocha-mauve-standard+default'"
dconf write /org/gnome/desktop/wm/preferences/titlebar-font "'$MAIN_FONT Bold $FONT_SIZE_SM'"

# Application menu
dconf write /org/gnome/desktop/wm/preferences/button-layout "'appmenu'"

# =============================================================================
# WALLPAPER CONFIGURATION (Catppuccin)
# =============================================================================
echo "🖼️  Catppuccin duvar kağıdı ayarları..."

# Ana duvar kağıdı
WALLPAPER_PATH="$HOME/Pictures/wallpapers/others/54.jpg"
if [ -f "$WALLPAPER_PATH" ]; then
  dconf write /org/gnome/desktop/background/picture-uri "'file://$WALLPAPER_PATH'"
  dconf write /org/gnome/desktop/background/picture-uri-dark "'file://$WALLPAPER_PATH'"
  dconf write /org/gnome/desktop/background/picture-options "'zoom'"
  echo "✅ Duvar kağıdı ayarlandı: $WALLPAPER_PATH"
else
  # Fallback solid color
  dconf write /org/gnome/desktop/background/color-shading-type "'solid'"
  dconf write /org/gnome/desktop/background/primary-color "'$MOCHA_BASE'"
  dconf write /org/gnome/desktop/background/picture-options "'none'"
  echo "⚠️  Duvar kağıdı bulunamadı, solid renk kullanılıyor"
fi

# Lock screen duvar kağıdı
LOCKSCREEN_PATH="$HOME/Pictures/wallpapers/others/54.jpg"
if [ -f "$LOCKSCREEN_PATH" ]; then
  dconf write /org/gnome/desktop/screensaver/picture-uri "'file://$LOCKSCREEN_PATH'"
else
  dconf write /org/gnome/desktop/screensaver/color-shading-type "'solid'"
  dconf write /org/gnome/desktop/screensaver/primary-color "'$MOCHA_MANTLE'"
fi

# =============================================================================
# AZWALLPAPER (WALLPAPER SLIDESHOW) CONFIGURATION
# =============================================================================
echo "🖼️  AzWallpaper (Wallpaper Slideshow) ayarları uygulanıyor..."

# Wallpaper dizini
WALLPAPER_DIR="$HOME/Pictures/wallpapers/others"
BING_DOWNLOAD_DIR="$HOME/Pictures/bing"

# Wallpaper dizinlerini oluştur
mkdir -p "$WALLPAPER_DIR"
mkdir -p "$BING_DOWNLOAD_DIR"

# Temel ayarlar
dconf write /org/gnome/shell/extensions/azwallpaper/slideshow-directory "'$WALLPAPER_DIR'"
dconf write /org/gnome/shell/extensions/azwallpaper/bing-download-directory "'$BING_DOWNLOAD_DIR'"
dconf write /org/gnome/shell/extensions/azwallpaper/bing-wallpaper-download "true"

# Slideshow zamanlaması - 5 dakikada bir değişsin (0 saat, 5 dakika, 0 saniye)
dconf write /org/gnome/shell/extensions/azwallpaper/slideshow-slide-duration "(0, 5, 0)"
dconf write /org/gnome/shell/extensions/azwallpaper/slideshow-use-absolute-time-for-duration "true"

# Preferences sayfası (boş - varsayılan)
dconf write /org/gnome/shell/extensions/azwallpaper/prefs-visible-page "''"

# Update notifier
dconf write /org/gnome/shell/extensions/azwallpaper/update-notifier-project-version "16"

echo "✅ AzWallpaper ayarları tamamlandı"
echo "   📁 Wallpaper dizini: $WALLPAPER_DIR"
echo "   📁 Bing indirme dizini: $BING_DOWNLOAD_DIR"
echo "   ⏱️  Değişim süresi: 5 dakika"
echo "   🌐 Bing otomatik indirme: Aktif"

# =============================================================================
# TERMINAL COLORS (Catppuccin Mocha için)
# =============================================================================
echo "💻 Terminal renk ayarları (Catppuccin Mocha)..."

# GNOME Terminal profili oluştur
TERMINAL_PROFILE_ID="catppuccin-mocha"
dconf write /org/gnome/terminal/legacy/profiles:/default "'$TERMINAL_PROFILE_ID'"
dconf write /org/gnome/terminal/legacy/profiles:/:$TERMINAL_PROFILE_ID/visible-name "'Catppuccin Mocha'"
dconf write /org/gnome/terminal/legacy/profiles:/:$TERMINAL_PROFILE_ID/use-theme-colors "false"
dconf write /org/gnome/terminal/legacy/profiles:/:$TERMINAL_PROFILE_ID/use-theme-transparency "false"
dconf write /org/gnome/terminal/legacy/profiles:/:$TERMINAL_PROFILE_ID/use-transparent-background "true"
dconf write /org/gnome/terminal/legacy/profiles:/:$TERMINAL_PROFILE_ID/background-transparency-percent "10"

# Catppuccin Mocha terminal renkleri
dconf write /org/gnome/terminal/legacy/profiles:/:$TERMINAL_PROFILE_ID/background-color "'$MOCHA_BASE'"
dconf write /org/gnome/terminal/legacy/profiles:/:$TERMINAL_PROFILE_ID/foreground-color "'$MOCHA_TEXT'"
dconf write /org/gnome/terminal/legacy/profiles:/:$TERMINAL_PROFILE_ID/bold-color "'$MOCHA_TEXT'"
dconf write /org/gnome/terminal/legacy/profiles:/:$TERMINAL_PROFILE_ID/bold-color-same-as-fg "true"
dconf write /org/gnome/terminal/legacy/profiles:/:$TERMINAL_PROFILE_ID/cursor-colors-set "true"
dconf write /org/gnome/terminal/legacy/profiles:/:$TERMINAL_PROFILE_ID/cursor-background-color "'$MOCHA_ROSEWATER'"
dconf write /org/gnome/terminal/legacy/profiles:/:$TERMINAL_PROFILE_ID/cursor-foreground-color "'$MOCHA_BASE'"
dconf write /org/gnome/terminal/legacy/profiles:/:$TERMINAL_PROFILE_ID/highlight-colors-set "true"
dconf write /org/gnome/terminal/legacy/profiles:/:$TERMINAL_PROFILE_ID/highlight-background-color "'$MOCHA_SURFACE2'"
dconf write /org/gnome/terminal/legacy/profiles:/:$TERMINAL_PROFILE_ID/highlight-foreground-color "'$MOCHA_TEXT'"

# Terminal palet renkleri (16 renk)
TERMINAL_PALETTE="['$MOCHA_SURFACE1', '$MOCHA_RED', '$MOCHA_GREEN', '$MOCHA_YELLOW', '$MOCHA_BLUE', '$MOCHA_PINK', '$MOCHA_TEAL', '$MOCHA_SUBTEXT1', '$MOCHA_SURFACE2', '$MOCHA_RED', '$MOCHA_GREEN', '$MOCHA_YELLOW', '$MOCHA_BLUE', '$MOCHA_PINK', '$MOCHA_TEAL', '$MOCHA_SUBTEXT0']"
dconf write /org/gnome/terminal/legacy/profiles:/:$TERMINAL_PROFILE_ID/palette "$TERMINAL_PALETTE"

# =============================================================================
# WINDOW MANAGER KEYBINDINGS
# =============================================================================
echo "⌨️  Window Manager keybinding'leri uygulanıyor..."

# Basic window management
dconf write /org/gnome/desktop/wm/keybindings/close "['<Super>q']"
dconf write /org/gnome/desktop/wm/keybindings/toggle-fullscreen "['<Super>f']"
# Keep <Super>m free for gnome-column-width toggle (Niri-like 0.8 <-> 1.0)
dconf write /org/gnome/desktop/wm/keybindings/toggle-maximized "['<Alt>g', '<Super>Up']"
dconf write /org/gnome/desktop/wm/keybindings/maximize "@as []"
dconf write /org/gnome/desktop/wm/keybindings/activate-window-menu "@as []"
dconf write /org/gnome/desktop/wm/keybindings/minimize "@as []"
dconf write /org/gnome/desktop/wm/keybindings/show-desktop "@as []"

# Niri-like alt-tab: switch windows (not apps)
dconf write /org/gnome/desktop/wm/keybindings/switch-windows "['<Alt>Tab', '<Super>Tab']"
dconf write /org/gnome/desktop/wm/keybindings/switch-windows-backward "['<Shift><Alt>Tab', '<Shift><Super>Tab']"
dconf write /org/gnome/desktop/wm/keybindings/switch-applications "@as []"
dconf write /org/gnome/desktop/wm/keybindings/switch-applications-backward "@as []"

# Workspace switching - DISABLED for custom history support
dconf write /org/gnome/desktop/wm/keybindings/switch-to-workspace-1 "@as []"
dconf write /org/gnome/desktop/wm/keybindings/switch-to-workspace-2 "@as []"
dconf write /org/gnome/desktop/wm/keybindings/switch-to-workspace-3 "@as []"
dconf write /org/gnome/desktop/wm/keybindings/switch-to-workspace-4 "@as []"
dconf write /org/gnome/desktop/wm/keybindings/switch-to-workspace-5 "@as []"
dconf write /org/gnome/desktop/wm/keybindings/switch-to-workspace-6 "@as []"
dconf write /org/gnome/desktop/wm/keybindings/switch-to-workspace-7 "@as []"
dconf write /org/gnome/desktop/wm/keybindings/switch-to-workspace-8 "@as []"
dconf write /org/gnome/desktop/wm/keybindings/switch-to-workspace-9 "@as []"
dconf write /org/gnome/desktop/wm/keybindings/switch-to-workspace-10 "@as []"

# Move window to workspace
dconf write /org/gnome/desktop/wm/keybindings/move-to-workspace-1 "['<Super><Shift>1']"
dconf write /org/gnome/desktop/wm/keybindings/move-to-workspace-2 "['<Super><Shift>2']"
dconf write /org/gnome/desktop/wm/keybindings/move-to-workspace-3 "['<Super><Shift>3']"
dconf write /org/gnome/desktop/wm/keybindings/move-to-workspace-4 "['<Super><Shift>4']"
dconf write /org/gnome/desktop/wm/keybindings/move-to-workspace-5 "['<Super><Shift>5']"
dconf write /org/gnome/desktop/wm/keybindings/move-to-workspace-6 "['<Super><Shift>6']"
dconf write /org/gnome/desktop/wm/keybindings/move-to-workspace-7 "['<Super><Shift>7']"
dconf write /org/gnome/desktop/wm/keybindings/move-to-workspace-8 "['<Super><Shift>8']"
dconf write /org/gnome/desktop/wm/keybindings/move-to-workspace-9 "['<Super><Shift>9']"

# Workspace navigation (VERTICAL like Niri: use k/j)
dconf write /org/gnome/desktop/wm/keybindings/switch-to-workspace-left "@as []"
dconf write /org/gnome/desktop/wm/keybindings/switch-to-workspace-right "@as []"
dconf write /org/gnome/desktop/wm/keybindings/switch-to-workspace-up "['<Super>k']"
dconf write /org/gnome/desktop/wm/keybindings/switch-to-workspace-down "['<Super>j']"

# Move window between workspaces (VERTICAL like Niri: PageUp/PageDown)
dconf write /org/gnome/desktop/wm/keybindings/move-to-workspace-left "@as []"
dconf write /org/gnome/desktop/wm/keybindings/move-to-workspace-right "@as []"
dconf write /org/gnome/desktop/wm/keybindings/move-to-workspace-up "['<Super>Page_Up']"
dconf write /org/gnome/desktop/wm/keybindings/move-to-workspace-down "['<Super>Page_Down']"

# =============================================================================
# SHELL KEYBINDINGS
# =============================================================================
echo "🐚 Shell keybinding'leri uygulanıyor..."

dconf write /org/gnome/shell/keybindings/toggle-application-view "['<Super>d', '<Super>a']"
dconf write /org/gnome/shell/keybindings/toggle-message-tray "['<Super>n']"
dconf write /org/gnome/shell/keybindings/show-screenshot-ui "['Print']"
dconf write /org/gnome/shell/keybindings/toggle-overview "['<Super><Alt>o']"

# Application switching keybinding'larını kapat (workspace çakışması için)
dconf write /org/gnome/shell/keybindings/switch-to-application-1 "@as []"
dconf write /org/gnome/shell/keybindings/switch-to-application-2 "@as []"
dconf write /org/gnome/shell/keybindings/switch-to-application-3 "@as []"
dconf write /org/gnome/shell/keybindings/switch-to-application-4 "@as []"
dconf write /org/gnome/shell/keybindings/switch-to-application-5 "@as []"
dconf write /org/gnome/shell/keybindings/switch-to-application-6 "@as []"
dconf write /org/gnome/shell/keybindings/switch-to-application-7 "@as []"
dconf write /org/gnome/shell/keybindings/switch-to-application-8 "@as []"
dconf write /org/gnome/shell/keybindings/switch-to-application-9 "@as []"

# =============================================================================
# NIGHT LIGHT (Mavi ışık filtresi)
# =============================================================================
echo "🌙 Night Light ayarları uygulanıyor..."

# 00:00 - 00:00 (24 saat) ve örnek sıcaklık değeri
NIGHT_LIGHT_FROM="0.0" # 00:00
NIGHT_LIGHT_TO="0.0"   # 00:00 (GNOME çoğu sürümde 24h anlamına gelir)
NIGHT_LIGHT_TEMP=2800  # 1000–10000 arası (daha sıcak = daha sarı)

dconf write /org/gnome/settings-daemon/plugins/color/night-light-enabled true
dconf write /org/gnome/settings-daemon/plugins/color/night-light-schedule-automatic false
dconf write /org/gnome/settings-daemon/plugins/color/night-light-temperature "uint32 $NIGHT_LIGHT_TEMP"
dconf write /org/gnome/settings-daemon/plugins/color/night-light-schedule-from "$NIGHT_LIGHT_FROM"
dconf write /org/gnome/settings-daemon/plugins/color/night-light-schedule-to "$NIGHT_LIGHT_TO"

# Not: Bazı GNOME derlemelerinde 0.0→0.0 tam-gün davranmıyorsa,
# yalnızca aşağıdaki satırı 24.0 yapman yeterli olur:
# dconf write /org/gnome/settings-daemon/plugins/color/night-light-schedule-to "24.0"

# =============================================================================
# MUTTER SETTINGS
# =============================================================================
echo "🪟 Mutter ayarları uygulanıyor..."

dconf write /org/gnome/mutter/edge-tiling "true"
dconf write /org/gnome/mutter/dynamic-workspaces "false"
dconf write /org/gnome/mutter/workspaces-only-on-primary "false"
dconf write /org/gnome/mutter/center-new-windows "true"
dconf write /org/gnome/mutter/focus-change-on-pointer-rest "true"
dconf write /org/gnome/mutter/auto-maximize "false"
dconf write /org/gnome/mutter/attach-modal-dialogs "true"

# =============================================================================
# WORKSPACE SETTINGS
# =============================================================================
echo "🏢 Workspace ayarları uygulanıyor..."

dconf write /org/gnome/desktop/wm/preferences/num-workspaces "9"
dconf write /org/gnome/desktop/wm/preferences/workspace-names "['1', '2', '3', '4', '5', '6', '7', '8', '9']"
dconf write /org/gnome/desktop/wm/preferences/focus-mode "'click'"
dconf write /org/gnome/desktop/wm/preferences/focus-new-windows "'smart'"
dconf write /org/gnome/desktop/wm/preferences/auto-raise "false"
dconf write /org/gnome/desktop/wm/preferences/raise-on-click "true"

# =============================================================================
# SHELL SETTINGS
# =============================================================================
echo "🐚 Shell ayarları uygulanıyor..."

dconf write /org/gnome/shell/favorite-apps "['brave-browser.desktop', 'kitty.desktop']"
# Needed for `org.gnome.Shell.Eval` (used by gnome-column-width / gnome-set).
dconf write /org/gnome/shell/development-tools "true"

# Best-effort: ensure required extensions are installed (vertical workspaces needs V-Shell)
if command -v gnome-extensions >/dev/null 2>&1 && command -v gnome-extensions-installer >/dev/null 2>&1; then
  if ! gnome-extensions list 2>/dev/null | grep -q "vertical-workspaces@G-dH.github.com"; then
    gnome-extensions-installer --install || true
  fi
fi

# Extensions - Linux'ta yüklü olanlar
EXTENSIONS="['audio-switch-shortcuts@dbatis.github.com','auto-move-windows@gnome-shell-extensions.gcampax.github.com','azwallpaper@azwallpaper.gitlab.com','bluetooth-quick-connect@bjarosze.gmail.com','clipboard-indicator@tudmotu.com','copyous@boerdereinar.dev','dash-to-panel@jderose9.github.com','disable-workspace-animation@ethnarque','extension-list@tu.berry','gnome-niri-parity@kenan','gsconnect@andyholmes.github.io','headphone-internal-switch@gustavomalta.github.com','just-perfection-desktop@just-perfection','launcher@hedgie.tech','mediacontrols@cliffniff.github.com','no-overview@fthx','notification-configurator@exposedcat','notification-icons@jiggak.io','no-titlebar-when-maximized@alec.ninja','space-bar@luchrioh','tilingshell@ferrarodomenico.com','tophat@fflewddur.github.io','trayIconsReloaded@selfmade.pl','vertical-workspaces@G-dH.github.com','veil@dagimg-dot','vpn-indicator@fthx','weatheroclock@CleoMenezesJr.github.io','zetadev@bootpaper']"

dconf write /org/gnome/shell/enabled-extensions "$EXTENSIONS"
dconf write /org/gnome/shell/disabled-extensions "@as []"

# Enable local extension immediately if available (no logout needed)
if command -v gnome-extensions >/dev/null 2>&1; then
  gnome-extensions enable "gnome-niri-parity@kenan" >/dev/null 2>&1 || true
fi

# =============================================================================
# APP SWITCHER SETTINGS
# =============================================================================
echo "🔄 App switcher ayarları uygulanıyor..."

dconf write /org/gnome/shell/app-switcher/current-workspace-only "false"
dconf write /org/gnome/shell/window-switcher/current-workspace-only "true"

# =============================================================================
# EXTENSION CONFIGURATIONS
# =============================================================================
echo "🧩 Extension ayarları uygulanıyor..."

# Clipboard Indicator
dconf write /org/gnome/shell/extensions/clipboard-indicator/toggle-menu "['<Super>v']"
dconf write /org/gnome/shell/extensions/clipboard-indicator/clear-history "@as []"
dconf write /org/gnome/shell/extensions/clipboard-indicator/prev-entry "@as []"
dconf write /org/gnome/shell/extensions/clipboard-indicator/next-entry "@as []"
dconf write /org/gnome/shell/extensions/clipboard-indicator/cache-size "50"
dconf write /org/gnome/shell/extensions/clipboard-indicator/display-mode "0"

# GSConnect
dconf write /org/gnome/shell/extensions/gsconnect/show-indicators "true"
dconf write /org/gnome/shell/extensions/gsconnect/show-offline "false"

# Bluetooth Quick Connect
dconf write /org/gnome/shell/extensions/bluetooth-quick-connect/show-battery-icon-on "true"
dconf write /org/gnome/shell/extensions/bluetooth-quick-connect/show-battery-value-on "true"

# V-Shell (Vertical Workspaces) — GNOME 49 horizontal → vertical
# 0 = Left (vertical), 1 = Right (vertical), 4 = Hide (vertical)
dconf write /org/gnome/shell/extensions/vertical-workspaces/ws-thumbnails-position "1"

# Vitals
dconf write /org/gnome/shell/extensions/vitals/hot-sensors "['_processor_usage_', '_memory_usage_', '_network-rx_max_', '_network-tx_max_']"
dconf write /org/gnome/shell/extensions/vitals/position-in-panel "2"
dconf write /org/gnome/shell/extensions/vitals/use-higher-precision "false"
dconf write /org/gnome/shell/extensions/vitals/alphabetize "true"
dconf write /org/gnome/shell/extensions/vitals/include-static-info "false"
dconf write /org/gnome/shell/extensions/vitals/show-icons "true"
dconf write /org/gnome/shell/extensions/vitals/show-battery "true"
dconf write /org/gnome/shell/extensions/vitals/unit-fahrenheit "false"
dconf write /org/gnome/shell/extensions/vitals/memory-measurement "0"
dconf write /org/gnome/shell/extensions/vitals/network-speed-format "1"
dconf write /org/gnome/shell/extensions/vitals/storage-measurement "0"
dconf write /org/gnome/shell/extensions/vitals/hide-zeros "true"
dconf write /org/gnome/shell/extensions/vitals/menu-centered "false"

# Spotify Controls
dconf write /org/gnome/shell/extensions/spotify-controls/show-track-info "false"
dconf write /org/gnome/shell/extensions/spotify-controls/position "'middle-right'"
dconf write /org/gnome/shell/extensions/spotify-controls/show-notifications "true"
dconf write /org/gnome/shell/extensions/spotify-controls/track-length "30"
dconf write /org/gnome/shell/extensions/spotify-controls/show-pause-icon "true"
dconf write /org/gnome/shell/extensions/spotify-controls/show-next-icon "true"
dconf write /org/gnome/shell/extensions/spotify-controls/show-prev-icon "true"
dconf write /org/gnome/shell/extensions/spotify-controls/button-color "'default'"
dconf write /org/gnome/shell/extensions/spotify-controls/hide-on-no-spotify "true"
dconf write /org/gnome/shell/extensions/spotify-controls/show-volume-control "false"
dconf write /org/gnome/shell/extensions/spotify-controls/show-album-art "false"
dconf write /org/gnome/shell/extensions/spotify-controls/compact-mode "true"

# Auto Move Windows (Niri-like workspace rules)
AUTO_MOVE_LIST="['helium-kenp.desktop:1','brave-browser.desktop:1','kitty.desktop:2','brave-ai.desktop:3','brave-compecta.desktop:4','discord.desktop:5','webcord.desktop:5','audacious.desktop:5','org.telegram.desktop.desktop:6','vlc.desktop:6','remote-viewer.desktop:6','transmission-gtk.desktop:7','org.keepassxc.KeePassXC.desktop:7','brave-youtube.com__-Default.desktop:7','brave-agimnkijcaahngcdmfeangaknmldooml-Default.desktop:7','spotify.desktop:8','ferdium.desktop:9','com.rtosta.zapzap.desktop:9','whatsie.desktop:9']"
dconf write /org/gnome/shell/extensions/auto-move-windows/application-list "$AUTO_MOVE_LIST"

# =============================================================================
# EXTENSION THEMING (Catppuccin Mocha)
# =============================================================================
echo "🧩 Extension tema ayarları (Catppuccin Mocha)..."

# Dash to Panel - Catppuccin renkleri
dconf write /org/gnome/shell/extensions/dash-to-panel/panel-element-positions-monitors-sync "true"
dconf write /org/gnome/shell/extensions/dash-to-panel/trans-use-custom-bg "true"
dconf write /org/gnome/shell/extensions/dash-to-panel/trans-bg-color "'$MOCHA_BASE'"
dconf write /org/gnome/shell/extensions/dash-to-panel/trans-use-custom-opacity "true"
dconf write /org/gnome/shell/extensions/dash-to-panel/trans-panel-opacity "0.95"

# Tiling Shell - Niri-like borders (active cyan, inactive surface1)
dconf write /org/gnome/shell/extensions/tilingshell/border-color "'$MOCHA_SURFACE1'"
dconf write /org/gnome/shell/extensions/tilingshell/active-window-border-color "'$NIRI_CYAN'"

# Space Bar - Catppuccin CSS güncelleme
SPACE_BAR_MOCHA_CSS='
.space-bar {
  -natural-hpadding: 12px;
  background-color: '"$MOCHA_BASE"';
}

.space-bar-workspace-label.active {
  margin: 0 4px;
  background-color: '"$MOCHA_MAUVE"';
  color: '"$MOCHA_BASE"';
  border-color: transparent;
  font-weight: 700;
  border-radius: 6px;
  border-width: 0px;
  padding: 4px 10px;
  box-shadow: 0 2px 4px rgba(0,0,0,0.2);
}

.space-bar-workspace-label.inactive {
  margin: 0 4px;
  background-color: '"$MOCHA_SURFACE0"';
  color: '"$MOCHA_TEXT"';
  border-color: transparent;
  font-weight: 500;
  border-radius: 6px;
  border-width: 0px;
  padding: 4px 10px;
  transition: all 0.2s ease;
}

.space-bar-workspace-label.inactive:hover {
  background-color: '"$MOCHA_SURFACE1"';
  color: '"$MOCHA_SUBTEXT1"';
}

.space-bar-workspace-label.inactive.empty {
  margin: 0 4px;
  background-color: transparent;
  color: '"$MOCHA_OVERLAY0"';
  border-color: transparent;
  font-weight: 400;
  border-radius: 6px;
  border-width: 0px;
  padding: 4px 10px;
}
'

dconf write /org/gnome/shell/extensions/space-bar/appearance/application-styles "'$SPACE_BAR_MOCHA_CSS'"

# =============================================================================
# PRIVACY SETTINGS
# =============================================================================
echo "🔒 Privacy ayarları uygulanıyor..."

dconf write /org/gnome/desktop/privacy/report-technical-problems "false"
dconf write /org/gnome/desktop/privacy/send-software-usage-stats "false"
dconf write /org/gnome/desktop/privacy/disable-microphone "false"
dconf write /org/gnome/desktop/privacy/disable-camera "false"

# =============================================================================
# POWER SETTINGS
# =============================================================================
echo "⚡ Power ayarları uygulanıyor..."

dconf write /org/gnome/settings-daemon/plugins/power/sleep-inactive-ac-type "'suspend'"
dconf write /org/gnome/settings-daemon/plugins/power/sleep-inactive-ac-timeout "3600"
dconf write /org/gnome/settings-daemon/plugins/power/sleep-inactive-battery-type "'suspend'"
dconf write /org/gnome/settings-daemon/plugins/power/sleep-inactive-battery-timeout "3600"
dconf write /org/gnome/settings-daemon/plugins/power/power-button-action "'interactive'"
dconf write /org/gnome/settings-daemon/plugins/power/handle-lid-switch "false"

# =============================================================================
# SESSION SETTINGS
# =============================================================================
echo "🖥️  Session ayarları uygulanıyor..."

dconf write /org/gnome/desktop/session/idle-delay "uint32 0"

# =============================================================================
# TOUCHPAD SETTINGS
# =============================================================================
echo "👆 Touchpad ayarları uygulanıyor..."

dconf write /org/gnome/desktop/peripherals/touchpad/tap-to-click "true"
dconf write /org/gnome/desktop/peripherals/touchpad/two-finger-scrolling-enabled "true"
dconf write /org/gnome/desktop/peripherals/touchpad/natural-scroll "false"
dconf write /org/gnome/desktop/peripherals/touchpad/disable-while-typing "true"
dconf write /org/gnome/desktop/peripherals/touchpad/click-method "'fingers'"
dconf write /org/gnome/desktop/peripherals/touchpad/send-events "'enabled'"
dconf write /org/gnome/desktop/peripherals/touchpad/speed "0.8"
dconf write /org/gnome/desktop/peripherals/touchpad/accel-profile "'default'"
dconf write /org/gnome/desktop/peripherals/touchpad/scroll-method "'two-finger-scrolling'"
dconf write /org/gnome/desktop/peripherals/touchpad/middle-click-emulation "false"

# =============================================================================
# MOUSE SETTINGS
# =============================================================================
echo "🖱️  Mouse ayarları uygulanıyor..."

dconf write /org/gnome/desktop/peripherals/mouse/natural-scroll "false"
dconf write /org/gnome/desktop/peripherals/mouse/speed "0.0"

# =============================================================================
# SOUND SETTINGS
# =============================================================================
echo "🔊 Sound ayarları uygulanıyor..."

dconf write /org/gnome/desktop/sound/event-sounds "true"
dconf write /org/gnome/desktop/sound/theme-name "'freedesktop'"

# =============================================================================
# SCREENSAVER SETTINGS
# =============================================================================
echo "🔒 Screensaver ayarları uygulanıyor..."

dconf write /org/gnome/desktop/screensaver/lock-enabled "true"
dconf write /org/gnome/desktop/screensaver/lock-delay "uint32 0"
dconf write /org/gnome/desktop/screensaver/idle-activation-enabled "true"

## =============================================================================
## LOCK SCREEN DISABLE (AUTOLOGIN İÇİN)
## =============================================================================
#echo "🔓 Kilit ekranı devre dışı bırakılıyor (autologin için)..."

#dconf write /org/gnome/desktop/lockdown/disable-lock-screen "true"
#dconf write /org/gnome/desktop/screensaver/lock-enabled "false"
#dconf write /org/gnome/desktop/screensaver/idle-activation-enabled "false"
#dconf write /org/gnome/desktop/session/idle-delay "uint32 0"

#echo "✅ Kilit ekranı tamamen devre dışı bırakıldı"

# =============================================================================
# LOCK SCREEN SETTINGS
# =============================================================================
echo "🔒 Kilit ekranı ayarları yapılıyor..."

dconf write /org/gnome/desktop/lockdown/disable-lock-screen "false"
dconf write /org/gnome/desktop/screensaver/lock-enabled "true"
dconf write /org/gnome/desktop/screensaver/lock-delay "uint32 0"
dconf write /org/gnome/desktop/screensaver/idle-activation-enabled "true"
dconf write /org/gnome/desktop/session/idle-delay "uint32 1800"

echo "✅ Kilit ekranı aktif (30 dakika idle sonra, Alt+L ile manuel)"
# =============================================================================
# NAUTILUS SETTINGS
# =============================================================================
echo "📁 Nautilus ayarları uygulanıyor..."

dconf write /org/gnome/nautilus/preferences/default-folder-viewer "'list-view'"
dconf write /org/gnome/nautilus/preferences/search-filter-time-type "'last_modified'"
dconf write /org/gnome/nautilus/preferences/show-hidden-files "false"
dconf write /org/gnome/nautilus/preferences/show-create-link "true"

dconf write /org/gnome/nautilus/list-view/use-tree-view "true"
dconf write /org/gnome/nautilus/list-view/default-zoom-level "'small'"

# =============================================================================
# FILE MANAGER THEME (Nemo için Catppuccin)
# =============================================================================
echo "📁 Dosya yöneticisi tema ayarları..."

# Nemo için GTK CSS
NEMO_CSS_DIR="$HOME/.config/gtk-3.0"
mkdir -p "$NEMO_CSS_DIR"

cat >"$NEMO_CSS_DIR/gtk.css" <<EOF
/* Catppuccin Mocha Nemo Customizations */
.nemo-window {
    background-color: $MOCHA_BASE;
    color: $MOCHA_TEXT;
}

.nemo-window .toolbar {
    background-color: $MOCHA_MANTLE;
    border-bottom: 1px solid $MOCHA_SURFACE0;
}

.nemo-window .sidebar {
    background-color: $MOCHA_MANTLE;
    border-right: 1px solid $MOCHA_SURFACE0;
}

.nemo-window .view {
    background-color: $MOCHA_BASE;
    color: $MOCHA_TEXT;
}

.nemo-window .view:selected {
    background-color: $MOCHA_MAUVE;
    color: $MOCHA_BASE;
}
EOF

# =============================================================================
# CURSORS AND ICONS
# =============================================================================
echo "🎯 Cursor ve ikon ayarları..."

# Cursor size for HiDPI
if xrandr | grep -q "3840x2160\|2560x1440"; then
  dconf write /org/gnome/desktop/interface/cursor-size "24"
  echo "🖥️  HiDPI ekran tespit edildi, cursor boyutu 32'ye ayarlandı"
else
  dconf write /org/gnome/desktop/interface/cursor-size "20"
fi

# =============================================================================
# NOTIFICATION STYLING
# =============================================================================
echo "🔔 Bildirim ayarları..."

# Notification timeout
dconf write /org/gnome/desktop/notifications/show-in-lock-screen "false"
dconf write /org/gnome/desktop/notifications/show-banners "true"

# =============================================================================
# CUSTOM KEYBINDINGS (0..54) — absolute paths, no PATH lookups
# =============================================================================
echo "⌨️  Custom keybinding'ler (0..54) yazılıyor..."

# --- helpers: resolve absolute paths
opt() {
  local n="$1"
  local cand

  # 1) PATH içinde varsa
  cand="$(command -v "$n" 2>/dev/null || true)"
  if [ -n "$cand" ] && [ -x "$cand" ]; then
    printf '%s' "$cand"
    return 0
  fi

  # 2) Yaygın kullanıcı dizinleri
  for cand in \
    "$HOME/.local/bin/$n" \
    "$HOME/bin/$n"; do
    if [ -x "$cand" ]; then
      printf '%s' "$cand"
      return 0
    fi
  done

  # 3) yoksa son çare isim (ama bu gecikme demek!)
  printf '%s' "$n"
}

KITTY="$(opt kitty)"
BRAVE="$(opt brave || opt brave-browser)"
YAZI="$(opt yazi)"
NEMO="$(opt nemo)"
WALKER="$(opt walker)"
ROFI_LAUNCHER="$(opt rofi-launcher)"
COPYQ="$(opt copyq)"
WEBCORD="$(opt webcord)"
WMCTRL="$(opt wmctrl)"
LOGINCTL="$(opt loginctl)"

OSC_NDROP="$(opt osc-ndrop)"
OSC_SOUNDCTL="$(opt osc-soundctl)"
OSC_SPOTIFY="$(opt osc-spotify)"
OSC_REBOOT="$(opt osc-safe-reboot)"
BLUE_TOGGLE="$(opt bluetooth_toggle)"
VLC_TOGGLE="$(opt vlc-toggle)"
MPC_CONTROL="$(opt mpc-control)"
NSTICKY_TOGGLE="$(opt nsticky-toggle)"
MPV_MGR="$(opt mpv-manager)"
KKENP="$(opt start-kkenp)"
SEM_SUMO="$(opt semsumo)"
WSPREV="$(opt ws-prev)"
WSNEXT="$(opt ws-next)"
MULLVAD="$(opt osc-mullvad)"
SCREENSHOT="$(opt gnome-screenshot)"
GKR="$(opt gnome-kr-fix)"
WALK="$(opt walk)"
GNOME_COLWIDTH="$(opt gnome-column-width)"
GNOME_SET="$(opt gnome-set)"

# 0..54 path list
CUSTOM_PATHS=""
for i in {0..54}; do
  p="/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom${i}/"
  if [ -z "$CUSTOM_PATHS" ]; then
    CUSTOM_PATHS="'$p'"
  else
    CUSTOM_PATHS="$CUSTOM_PATHS, '$p'"
  fi
done
dconf write /org/gnome/settings-daemon/plugins/media-keys/custom-keybindings "[ $CUSTOM_PATHS ]"

# 0) Terminal
dconf write /org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom0/binding "'<Super>t'"
dconf write /org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom0/command "'$KITTY'"
dconf write /org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom0/name "'Terminal'"

# 1) Browser
dconf write /org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom1/binding "'<Super>b'"
dconf write /org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom1/command "'$BRAVE'"
dconf write /org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom1/name "'Browser'"

# 2) Dropdown terminal (Niri-style)
dconf write /org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom2/binding "'<Super>Return'"
dconf write /org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom2/command "'$OSC_NDROP $KITTY --class dropdown-terminal'"
dconf write /org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom2/name "'Dropdown Terminal'"

# 3) Nemo
dconf write /org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom3/binding "'<Super><Ctrl>f'"
dconf write /org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom3/command "'$NEMO'"
dconf write /org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom3/name "'Open Nemo File Manager'"

# 4) Terminal FM (yazi)
dconf write /org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom4/binding "'<Alt><Ctrl>f'"
dconf write /org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom4/command "'$KITTY -e $YAZI'"
dconf write /org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom4/name "'Terminal File Manager (Yazi)'"

# 5) Rofi Launcher (Niri-style)
dconf write /org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom5/binding "'<Alt>space'"
dconf write /org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom5/command "'$ROFI_LAUNCHER'"
dconf write /org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom5/name "'Rofi Launcher'"

# 6) Audio output switch
dconf write /org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom6/binding "'<Alt>a'"
dconf write /org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom6/command "'$OSC_SOUNDCTL switch'"
dconf write /org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom6/name "'Switch Audio Output'"

# 7) Mic switch
dconf write /org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom7/binding "'<Alt><Ctrl>a'"
dconf write /org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom7/command "'$OSC_SOUNDCTL switch-mic'"
dconf write /org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom7/name "'Switch Microphone'"

# 8) Spotify toggle
dconf write /org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom8/binding "'<Alt>e'"
dconf write /org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom8/command "'$OSC_SPOTIFY'"
dconf write /org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom8/name "'Spotify Toggle'"

# 9) Spotify next
dconf write /org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom9/binding "'<Alt><Ctrl>n'"
dconf write /org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom9/command "'$OSC_SPOTIFY next'"
dconf write /org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom9/name "'Spotify Next'"

# 10) Spotify prev
dconf write /org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom10/binding "'<Alt><Ctrl>b'"
dconf write /org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom10/command "'$OSC_SPOTIFY prev'"
dconf write /org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom10/name "'Spotify Previous'"

# 11) VLC toggle (Niri-style)
dconf write /org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom11/binding "'<Alt>i'"
dconf write /org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom11/command "'$VLC_TOGGLE'"
dconf write /org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom11/name "'VLC Toggle'"

# 12) Lock screen
dconf write /org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom12/binding "'<Alt>l'"
dconf write /org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom12/command "'$LOGINCTL lock-session'"
dconf write /org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom12/name "'Lock Screen'"

# 13) Prev workspace
dconf write /org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom13/binding "'<Super><Alt>Up'"
dconf write /org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom13/command "'$WSPREV'"
dconf write /org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom13/name "'Previous Workspace'"

# 14) Next workspace
dconf write /org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom14/binding "'<Super><Alt>Down'"
dconf write /org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom14/command "'$WSNEXT'"
dconf write /org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom14/name "'Next Workspace'"

# 15) Discord (WebCord)
dconf write /org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom15/binding "'<Super><Shift>d'"
dconf write /org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom15/command "'$WEBCORD --enable-features=UseOzonePlatform --ozone-platform=wayland'"
dconf write /org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom15/name "'Open Discord'"

# 16) KKENP
dconf write /org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom16/binding "'<Alt>t'"
dconf write /org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom16/command "'$KKENP'"
dconf write /org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom16/name "'Start KKENP'"

# 17) Notes (Anotes)
dconf write /org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom17/binding "'<Alt>n'"
dconf write /org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom17/command "'anotes'"
dconf write /org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom17/name "'Notes (Anotes)'"

# 18) Clipboard (CopyQ)
dconf write /org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom18/binding "'<Super>v'"
dconf write /org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom18/command "'$COPYQ toggle'"
dconf write /org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom18/name "'Clipboard Manager'"

# 19) Bluetooth toggle
dconf write /org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom19/binding "'F10'"
dconf write /org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom19/command "'$BLUE_TOGGLE'"
dconf write /org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom19/name "'Bluetooth Toggle'"

# 20) Mullvad (VPN)
dconf write /org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom20/binding "'<Alt>F12'"
dconf write /org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom20/command "'$MULLVAD toggle'"
dconf write /org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom20/name "'Mullvad Toggle'"

# 21) Gnome Start
dconf write /org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom21/binding "'<Super><Alt>Return'"
dconf write /org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom21/command "'$SEM_SUMO launch --daily -all'"
dconf write /org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom21/name "'Gnome Start'"

# 22) Column Width Cycle (Niri: Mod+R)
dconf write /org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom22/binding "'<Super>r'"
dconf write /org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom22/command "'$GNOME_COLWIDTH'"
dconf write /org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom22/name "'Column Width Cycle'"

# 23) Column Width 80% (Niri: Mod+Shift+R)
dconf write /org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom23/binding "'<Super><Shift>r'"
dconf write /org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom23/command "'$GNOME_COLWIDTH set 0.8'"
dconf write /org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom23/name "'Column Width 80%'"

# 24) Column Width Toggle (0.8 <-> 1.0) (Niri: Mod+M)
dconf write /org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom24/binding "'<Super>m'"
dconf write /org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom24/command "'$GNOME_COLWIDTH toggle'"
dconf write /org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom24/name "'Column Width Toggle'"

# 25) MPV Playback (Niri-style)
dconf write /org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom25/binding "'<Alt>u'"
dconf write /org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom25/command "'$MPV_MGR playback'"
dconf write /org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom25/name "'MPV Playback'"

# 26) MPV Play YouTube (Niri-style)
dconf write /org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom26/binding "'<Super><Ctrl>y'"
dconf write /org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom26/command "'$MPV_MGR play-yt'"
dconf write /org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom26/name "'MPV Play YouTube'"

# 27) MPV Stick (Niri-style)
dconf write /org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom27/binding "'<Super><Ctrl>F9'"
dconf write /org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom27/command "'$MPV_MGR stick'"
dconf write /org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom27/name "'MPV Stick'"

# 28) MPV Move (Niri-style)
dconf write /org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom28/binding "'<Super><Ctrl>F10'"
dconf write /org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom28/command "'$MPV_MGR move'"
dconf write /org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom28/name "'MPV Move'"

# 29) MPV Save YouTube (Niri-style)
dconf write /org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom29/binding "'<Super><Ctrl>F11'"
dconf write /org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom29/command "'$MPV_MGR save-yt'"
dconf write /org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom29/name "'MPV Save YouTube'"

# 30) MPV Wallpaper (Niri-style)
dconf write /org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom30/binding "'<Super><Ctrl>F12'"
dconf write /org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom30/command "'$MPV_MGR wallpaper'"
dconf write /org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom30/name "'MPV Wallpaper'"

# 31) Sticky Toggle (Niri-style)
dconf write /org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom31/binding "'<Super><Ctrl>s'"
dconf write /org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom31/command "'$NSTICKY_TOGGLE'"
dconf write /org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom31/name "'Sticky Toggle'"

# 32) MPC Toggle (Niri-style)
dconf write /org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom32/binding "'<Alt><Ctrl>e'"
dconf write /org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom32/command "'$MPC_CONTROL toggle'"
dconf write /org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom32/name "'MPC Toggle'"

# 33) (unused)
dconf write /org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom33/binding "''"
dconf write /org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom33/command "'true'"
dconf write /org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom33/name "'(unused)'"

# 34) (unused)
dconf write /org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom34/binding "''"
dconf write /org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom34/command "'true'"
dconf write /org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom34/name "'(unused)'"

# 35) (unused)
dconf write /org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom35/binding "''"
dconf write /org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom35/command "'true'"
dconf write /org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom35/name "'(unused)'"

# 36) (unused)
dconf write /org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom36/binding "''"
dconf write /org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom36/command "'true'"
dconf write /org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom36/name "'(unused)'"

# 44) Here: Kenp
dconf write /org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom44/binding "'<Alt>1'"
dconf write /org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom44/command "'$GNOME_SET here Kenp'"
dconf write /org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom44/name "'Here: Kenp'"

# 45) Here: TmuxKenp
dconf write /org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom45/binding "'<Alt>2'"
dconf write /org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom45/command "'$GNOME_SET here TmuxKenp'"
dconf write /org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom45/name "'Here: TmuxKenp'"

# 46) Here: Ai
dconf write /org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom46/binding "'<Alt>3'"
dconf write /org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom46/command "'$GNOME_SET here Ai'"
dconf write /org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom46/name "'Here: Ai'"

# 47) Here: CompecTA
dconf write /org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom47/binding "'<Alt>4'"
dconf write /org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom47/command "'$GNOME_SET here CompecTA'"
dconf write /org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom47/name "'Here: CompecTA'"

# 48) Here: WebCord
dconf write /org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom48/binding "'<Alt>5'"
dconf write /org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom48/command "'$GNOME_SET here WebCord'"
dconf write /org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom48/name "'Here: WebCord'"

# 49) Here: Telegram
dconf write /org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom49/binding "'<Alt>6'"
dconf write /org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom49/command "'$GNOME_SET here org.telegram.desktop'"
dconf write /org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom49/name "'Here: Telegram'"

# 50) Here: YouTube
dconf write /org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom50/binding "'<Alt>7'"
dconf write /org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom50/command "'$GNOME_SET here brave-youtube.com__-Default'"
dconf write /org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom50/name "'Here: YouTube'"

# 51) Here: Spotify
dconf write /org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom51/binding "'<Alt>8'"
dconf write /org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom51/command "'$GNOME_SET here spotify'"
dconf write /org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom51/name "'Here: Spotify'"

# 52) Here: Ferdium
dconf write /org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom52/binding "'<Alt>9'"
dconf write /org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom52/command "'$GNOME_SET here ferdium'"
dconf write /org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom52/name "'Here: Ferdium'"

# 53) Here: ALL
dconf write /org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom53/binding "'<Alt>0'"
dconf write /org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom53/command "'$GNOME_SET here all'"
dconf write /org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom53/name "'Here: ALL'"

# 54) Arrange Windows (Go)
dconf write /org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom54/binding "'<Super><Alt>0'"
dconf write /org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom54/command "'$GNOME_SET go'"
dconf write /org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom54/name "'Arrange Windows (Go)'"

# 37) Shutdown
dconf write /org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom37/binding "'<Ctrl><Alt><Shift>s'"
dconf write /org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom37/command "'gnome-session-quit --power-off --no-prompt'"
dconf write /org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom37/name "'Shutdown Computer'"

# 38) Restart
dconf write /org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom38/binding "'<Ctrl><Alt>r'"
dconf write /org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom38/command "'gnome-session-quit --reboot --no-prompt'"
dconf write /org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom38/name "'Restart Computer'"

# 39) Logout
dconf write /org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom39/binding "'<Ctrl><Alt>q'"
dconf write /org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom39/command "'gnome-session-quit --logout --no-prompt'"
dconf write /org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom39/name "'Logout'"

# 40) Power menu (confirm)
dconf write /org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom40/binding "'<Ctrl><Alt>p'"
dconf write /org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom40/command "'gnome-session-quit --power-off'"
dconf write /org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom40/name "'Power Menu (with confirmation)'"

# 41) GKR
dconf write /org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom41/binding "'<Super><Ctrl><Alt>F12'"
dconf write /org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom41/command "'$GKR'"
dconf write /org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom41/name "'GNOME GKR'"

# 42) Walker
dconf write /org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom42/binding "'<Super><Ctrl>space'"
dconf write /org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom42/command "'$WALK'"
dconf write /org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom42/name "'WalkerS'"

# 43) Safe Reboot
dconf write /org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom43/binding "'<Super>backspace'"
dconf write /org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom43/command "'$OSC_REBOOT'"
dconf write /org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom43/name "'OSC Reboot'"

# =============================================================================
# GNOME'UN VARSAYILAN SUPER+[1-9] KISA YOLLARINI KAPAT
# =============================================================================
echo "🚫 GNOME varsayılan Super+[1-9] kısayolları devre dışı bırakılıyor..."

# Uygulama başlatma kısayollarını kapat (Super+[1-9])
for i in {1..9}; do
  dconf write /org/gnome/shell/keybindings/switch-to-application-$i "@as []"
done

# Workspace geçiş kısayollarını AYARLA (Super+[1-9])
for i in {1..9}; do
  dconf write /org/gnome/desktop/wm/keybindings/switch-to-workspace-$i "['<Super>$i']"
  dconf write /org/gnome/desktop/wm/keybindings/move-to-workspace-$i "['<Super><Shift>$i']"
done

# Space Bar extension'ının workspace switching kısayolunu etkinleştir (veya varsayılana bırak)
echo "🔧 Space Bar extension kısayolları kontrol ediliyor..."
dconf write /org/gnome/shell/extensions/space-bar/shortcuts/enable-activate-workspace-shortcuts true

echo "✅ Varsayılan Super+[1-9] kısayolları ayarlandı."
echo "💡 Super+[1-9] ile workspace geçişi yapabilirsiniz."

# =============================================================================
# EXTENSION COMPLEX CONFIGURATIONS
# =============================================================================
echo "🎨 Karmaşık extension ayarları uygulanıyor..."

# Dash to Panel - JSON Configuration
echo "📊 Dash to Panel ayarları..."

dconf write /org/gnome/shell/extensions/dash-to-panel/appicon-margin "8"
dconf write /org/gnome/shell/extensions/dash-to-panel/appicon-padding "4"
dconf write /org/gnome/shell/extensions/dash-to-panel/show-favorites "true"
dconf write /org/gnome/shell/extensions/dash-to-panel/show-running-apps "true"
dconf write /org/gnome/shell/extensions/dash-to-panel/show-window-previews "true"
dconf write /org/gnome/shell/extensions/dash-to-panel/isolate-workspaces "false"
dconf write /org/gnome/shell/extensions/dash-to-panel/group-apps "true"
dconf write /org/gnome/shell/extensions/dash-to-panel/dot-position "'BOTTOM'"
dconf write /org/gnome/shell/extensions/dash-to-panel/window-preview-title-position "'TOP'"
dconf write /org/gnome/shell/extensions/dash-to-panel/hotkeys-overlay-combo "'TEMPORARILY'"
dconf write /org/gnome/shell/extensions/dash-to-panel/intellihide "false"

# Panel positions - JSON string
dconf write /org/gnome/shell/extensions/dash-to-panel/panel-positions '"{\"CMN-0x00000000\":\"TOP\",\"DEL-KRXTR88N909L\":\"TOP\"}"'
dconf write /org/gnome/shell/extensions/dash-to-panel/panel-sizes '"{\"CMN-0x00000000\":28,\"DEL-KRXTR88N909L\":28}"'
dconf write /org/gnome/shell/extensions/dash-to-panel/panel-lengths '"{\"CMN-0x00000000\":100,\"DEL-KRXTR88N909L\":100}"'
dconf write /org/gnome/shell/extensions/dash-to-panel/panel-anchors '"{\"CMN-0x00000000\":\"MIDDLE\",\"DEL-KRXTR88N909L\":\"MIDDLE\"}"'

# Tiling Shell Configuration
echo "🪟 Tiling Shell ayarları..."

dconf write /org/gnome/shell/extensions/tilingshell/enable-tiling-system "true"
dconf write /org/gnome/shell/extensions/tilingshell/auto-tile "true"
dconf write /org/gnome/shell/extensions/tilingshell/snap-assist "true"
dconf write /org/gnome/shell/extensions/tilingshell/default-layout "'split'"
dconf write /org/gnome/shell/extensions/tilingshell/inner-gaps "12"
dconf write /org/gnome/shell/extensions/tilingshell/outer-gaps "12"

# Window Suggestions
dconf write /org/gnome/shell/extensions/tilingshell/enable-window-suggestions "true"
dconf write /org/gnome/shell/extensions/tilingshell/window-suggestions-for-snap-assist "true"
dconf write /org/gnome/shell/extensions/tilingshell/window-suggestions-for-edge-tiling "true"
dconf write /org/gnome/shell/extensions/tilingshell/window-suggestions-for-keybinding "true"
dconf write /org/gnome/shell/extensions/tilingshell/suggestions-timeout "3000"
dconf write /org/gnome/shell/extensions/tilingshell/max-suggestions-to-show "6"
dconf write /org/gnome/shell/extensions/tilingshell/enable-suggestions-scroll "true"

# Tiling Keybindings
dconf write /org/gnome/shell/extensions/tilingshell/tile-left "['<Super><Shift>Left', '<Super><Shift>h']"
dconf write /org/gnome/shell/extensions/tilingshell/tile-right "['<Super><Shift>Right', '<Super><Shift>l']"
dconf write /org/gnome/shell/extensions/tilingshell/tile-up "['<Super><Shift>Up', '<Super><Shift>k']"
dconf write /org/gnome/shell/extensions/tilingshell/tile-down "['<Super><Shift>Down', '<Super><Shift>j']"
dconf write /org/gnome/shell/extensions/tilingshell/toggle-tiling "@as []"
dconf write /org/gnome/shell/extensions/tilingshell/toggle-floating "['<Super>g', '<Super><Ctrl>BackSpace']"

# Focus keybindings
dconf write /org/gnome/shell/extensions/tilingshell/focus-left "['<Super>Left', '<Super>h']"
dconf write /org/gnome/shell/extensions/tilingshell/focus-right "['<Super>Right', '<Super>l']"
dconf write /org/gnome/shell/extensions/tilingshell/focus-up "['<Super><Ctrl>Up', '<Super><Ctrl>k']"
dconf write /org/gnome/shell/extensions/tilingshell/focus-down "['<Super><Ctrl>Down', '<Super><Ctrl>j']"

# Focus settings
dconf write /org/gnome/shell/extensions/tilingshell/auto-focus-on-tile "true"
dconf write /org/gnome/shell/extensions/tilingshell/focus-follows-mouse "false"
dconf write /org/gnome/shell/extensions/tilingshell/respect-focus-hints "true"

# Layout switching
dconf write /org/gnome/shell/extensions/tilingshell/next-layout "['<Super><Ctrl>Tab']"
dconf write /org/gnome/shell/extensions/tilingshell/prev-layout "['<Super><Shift><Ctrl>Tab']"

# Visual settings
dconf write /org/gnome/shell/extensions/tilingshell/show-border "true"
dconf write /org/gnome/shell/extensions/tilingshell/border-width "3"
dconf write /org/gnome/shell/extensions/tilingshell/enable-animations "true"
dconf write /org/gnome/shell/extensions/tilingshell/animation-duration "150"
dconf write /org/gnome/shell/extensions/tilingshell/resize-step "50"

# Advanced settings
dconf write /org/gnome/shell/extensions/tilingshell/respect-workspaces "true"
dconf write /org/gnome/shell/extensions/tilingshell/tile-dialogs "false"
dconf write /org/gnome/shell/extensions/tilingshell/tile-modals "false"
dconf write /org/gnome/shell/extensions/tilingshell/last-version-name-installed "'16.4'"

# =============================================================================
# CATPPUCCIN ENVIRONMENT VARIABLES
# =============================================================================
echo "🌍 Catppuccin ortam değişkenleri..."

# Prefer `environment.d` (systemd --user) for Nix/Home-Manager setups where
# ~/.profile may be a read-only symlink.
ENV_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/environment.d"
ENV_FILE="${ENV_DIR}/99-catppuccin.conf"
if mkdir -p "$ENV_DIR" 2>/dev/null; then
  cat >"$ENV_FILE" <<'EOF'
CATPPUCCIN_THEME=mocha
CATPPUCCIN_ACCENT=mauve
GTK_THEME=catppuccin-mocha-mauve-standard+default
XCURSOR_THEME=capitaine-cursors
XCURSOR_SIZE=24
EOF
  echo "✅ Catppuccin ortam değişkenleri $ENV_FILE içine yazıldı"
else
  echo "⚠️  $ENV_DIR oluşturulamadı; env yazımı atlandı"
fi

# Best-effort: also update current systemd/dbus activation environment.
if command -v systemctl >/dev/null 2>&1; then
  systemctl --user import-environment CATPPUCCIN_THEME CATPPUCCIN_ACCENT GTK_THEME XCURSOR_THEME XCURSOR_SIZE 2>/dev/null || true
fi
if command -v dbus-update-activation-environment >/dev/null 2>&1; then
  dbus-update-activation-environment --systemd CATPPUCCIN_THEME CATPPUCCIN_ACCENT GTK_THEME XCURSOR_THEME XCURSOR_SIZE 2>/dev/null || true
fi

# =============================================================================
# THEME VALIDATION
# =============================================================================
echo "✅ Catppuccin Mocha tema doğrulaması..."

# GTK tema kontrolü
if gsettings get org.gnome.desktop.interface gtk-theme | grep -q "catppuccin-mocha"; then
  echo "✅ GTK teması: Catppuccin Mocha aktif"
else
  echo "⚠️  GTK teması: Catppuccin Mocha aktif değil"
fi

# Icon tema kontrolü
if gsettings get org.gnome.desktop.interface icon-theme | grep -q "kora"; then
  echo "✅ İkon teması: Kora aktif"
else
  echo "⚠️  İkon teması: Varsayılan kullanılıyor"
fi

# Cursor tema kontrolü
if gsettings get org.gnome.desktop.interface cursor-theme | grep -q "catppuccin-mocha"; then
  echo "✅ Cursor teması: Catppuccin Mocha aktif"
else
  echo "⚠️  Cursor teması: Catppuccin Mocha aktif değil"
fi

# =============================================================================
# FINALIZATION
# =============================================================================
#echo "🔄 DConf güncelleniyor..."
#dconf update

#echo "🔧 GNOME Settings Daemon restart ediliyor..."
#pkill -f gnome-settings-daemon || true
#sleep 2
#nohup gnome-settings-daemon >/dev/null 2>&1 &

echo ""
echo "✅ GNOME + Catppuccin Mocha Konfigürasyonu başarıyla tamamlandı!"
echo "🕐 Bitiş zamanı: $(date)"
echo "📊 Script çalışma süresi: $SECONDS saniye"
echo ""
echo "🎨 Catppuccin Mocha Tema Özellikleri:"
echo "   • GTK Teması: catppuccin-mocha-mauve-standard+default"
echo "   • İkon Teması: kora"
echo "   • Cursor Teması: catppuccin-mocha-dark-cursors"
echo "   • Terminal Renkleri: Catppuccin Mocha paleti"
echo "   • Extension Temaları: Mocha renkleri ile uyumlu"
echo ""
echo "📋 Test etmek için temel keybinding'ler:"
echo "   🖥️  Super+t         → Terminal"
echo "   🌐 Super+b         → Browser"
echo "   📁 Super+e         → File Manager (Yazi)"
echo "   📁 Super+Ctrl+f    → Nemo File Manager"
echo "   📋 Super+v         → Clipboard"
echo "   🔎 Super+Space     → Spotlight (Walker)"
echo "   🚀 Super+Ctrl+Space → Launcher (walk)"
echo "   🪟 Super+Tab / Alt+Tab → Window Switcher"
echo "   🏢 Super+1-9       → Workspaces"
echo "   ❌ Super+q         → Close Window"
echo "   📸 Super+Shift+s   → Screenshot"
echo "   🔒 Alt+l           → Lock Screen"
echo ""
echo "🎨 Extension ayarları:"
echo "   📊 Dash to Panel   → Panel yapılandırması (Catppuccin renkli)"
echo "   🪟 Tiling Shell    → Window tiling sistemi (Mauve border)"
echo "   🌌 Space Bar       → Workspace göstergesi (Mocha tema)"
echo "   📋 Clipboard       → Super+v ile erişim"
echo "   💻 Vitals          → Sistem monitörü"
echo ""
echo "🎵 Medya Kontrolleri:"
echo "   🎧 Alt+e           → Spotify Toggle"
echo "   ⏭️  Alt+Ctrl+n      → Spotify Next"
echo "   ⏮️  Alt+Ctrl+b      → Spotify Previous"
echo "   🎬 Alt+i           → MPV Start/Focus"
echo "   ▶️  Alt+p           → MPV Toggle Playback"
echo ""
echo "🔧 Sistem Kontrolleri:"
echo "   🔊 Alt+a           → Audio Output Switch"
echo "   🎤 Alt+Ctrl+a      → Microphone Switch"
echo "   🔵 F10             → Bluetooth Toggle"
echo "   🔒 Alt+F12         → Mullvad VPN Toggle"
echo ""
echo "⚡ Güç Yönetimi:"
echo "   💤 Ctrl+Alt+Shift+s → Shutdown"
echo "   🔄 Ctrl+Alt+r       → Restart"
echo "   🚪 Ctrl+Alt+q       → Logout"
echo "   ⚙️  Ctrl+Alt+p       → Power Menu"
echo ""
echo "🏢 Workspace Yönetimi:"
echo "   ↑ Super+Alt+Up     → Previous Workspace"
echo "   ↓ Super+Alt+Down   → Next Workspace"
echo "   ⬆️ Super+k          → Workspace Up"
echo "   ⬇️ Super+j          → Workspace Down"
echo "   ⬆️ Super+PageUp     → Move Window Up"
echo "   ⬇️ Super+PageDown   → Move Window Down"
echo ""
echo "⚠️  Eğer bazı komutlar çalışmazsa:"
echo "   • O uygulamaların yüklü olduğundan emin olun"
echo "   • Extension'ları GNOME Extensions'dan kontrol edin"
echo "   • Logout/login yapın veya sistemi yeniden başlatın"
echo "   • Tema dosyalarının doğru konumda olduğunu kontrol edin"
echo ""
echo "🔍 Ayarları kontrol etmek için:"
echo "   gnome-control-center"
echo "   dconf-editor (detaylı ayarlar için)"
echo "   gsettings get org.gnome.desktop.interface gtk-theme"
echo ""
echo "🔧 Manuel kontrol komutları:"
echo "   gsettings get org.gnome.desktop.interface gtk-theme"
echo "   gsettings get org.gnome.desktop.interface icon-theme"
echo "   gsettings get org.gnome.desktop.interface cursor-theme"
echo ""
echo "📁 Tema dosyaları lokasyonu:"
echo "   ~/.themes/ (GTK temaları)"
echo "   ~/.icons/ (İkon temaları)"
echo "   ~/.local/share/icons/ (Cursor temaları)"
echo "   ~/.config/gtk-3.0/gtk.css (Nemo özelleştirmeleri)"
echo ""
echo "📁 Detaylı log dosyası: $LOG_FILE"
echo ""
echo "🎉 Catppuccin Mocha teması ile GNOME deneyiminizin keyfini çıkarın!"
echo "🔄 Değişikliklerin tam olarak uygulanması için logout/login yapın"

# Debug mode'u kapat
set +x
