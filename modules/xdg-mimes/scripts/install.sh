#!/usr/bin/env bash
set -euo pipefail

app_dir="${XDG_DATA_HOME:-$HOME/.local/share}/applications"
dbus_service_dir="${XDG_DATA_HOME:-$HOME/.local/share}/dbus-1/services"

if command -v update-desktop-database >/dev/null 2>&1; then
  update-desktop-database "$app_dir" >/dev/null 2>&1 || true
fi

# Default web browser -> Chrome (Kenp). Three resolvers each read a different
# store and drift apart otherwise: xdg-open (via xdg-mime query) is what most
# link clicks hit, gio mime is what GTK/GIO apps use, and xdg-settings is the
# umbrella. Pin all three to chrome-kenp so a clicked link always lands in the
# running Kenp Chrome (chrome-kenp.desktop -> `chromectl default %U`).
browser_desktop="chrome-kenp.desktop"
if [[ -f "$app_dir/$browser_desktop" ]]; then
  if command -v xdg-settings >/dev/null 2>&1; then
    xdg-settings set default-web-browser "$browser_desktop" >/dev/null 2>&1 || true
  fi
  if command -v xdg-mime >/dev/null 2>&1; then
    xdg-mime default "$browser_desktop" \
      x-scheme-handler/http x-scheme-handler/https text/html >/dev/null 2>&1 || true
  fi
  if command -v gio >/dev/null 2>&1; then
    gio mime x-scheme-handler/http "$browser_desktop" >/dev/null 2>&1 || true
    gio mime x-scheme-handler/https "$browser_desktop" >/dev/null 2>&1 || true
    gio mime text/html "$browser_desktop" >/dev/null 2>&1 || true
  fi
fi

if [[ -f "$app_dir/userapp-transmission-gtk-5ADTK3.desktop" ]]; then
  rm -f "$app_dir/userapp-transmission-gtk-5ADTK3.desktop"
fi

# Retire the previous user-level FileManager D-Bus overrides. They do not
# silence vendor warnings and only add extra duplicate-provider noise.
rm -f "$dbus_service_dir/org.freedesktop.FileManager1.service" \
  "$dbus_service_dir/org.Nemo.service"

# Ensure directory handlers resolve to Nemo for file attach/open flows.
if command -v xdg-mime >/dev/null 2>&1; then
  if [[ -f "$app_dir/transmission-gtk.desktop" ]] || [[ -f /usr/share/applications/transmission-gtk.desktop ]]; then
    xdg-mime default transmission-gtk.desktop x-scheme-handler/magnet >/dev/null 2>&1 || true
    xdg-mime default transmission-gtk.desktop application/x-bittorrent >/dev/null 2>&1 || true
  fi

  if command -v nemo >/dev/null 2>&1 || [[ -f /usr/share/applications/nemo.desktop ]]; then
    xdg-mime default nemo.desktop inode/directory >/dev/null 2>&1 || true
    xdg-mime default nemo.desktop application/x-directory >/dev/null 2>&1 || true
  fi
fi

if command -v gio >/dev/null 2>&1; then
  if [[ -f "$app_dir/transmission-gtk.desktop" ]] || [[ -f /usr/share/applications/transmission-gtk.desktop ]]; then
    gio mime x-scheme-handler/magnet transmission-gtk.desktop >/dev/null 2>&1 || true
    gio mime application/x-bittorrent transmission-gtk.desktop >/dev/null 2>&1 || true
  fi

  if command -v nemo >/dev/null 2>&1 || [[ -f /usr/share/applications/nemo.desktop ]]; then
    gio mime inode/directory nemo.desktop >/dev/null 2>&1 || true
  fi
fi
