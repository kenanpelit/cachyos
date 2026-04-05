# Arch Updater
A plugin designed to allow you to see available updates, the currently installed version and the updated version.<br>
With optional Flatpak support, highlight for Noctalia updates, a refresh timer, hide on empty and toasts.


## Features

**Bar Widget**
- Update count
- Left click to open panel
- Right click to open context menu
- Middle click to refresh
- Tooltip with updates list

**Panel**
- Table of updates
- Refresh/Update buttons

**Desktop Widget**
- Update count
- Table of updates
- Left click to refresh
- Middle click to update

**IPC**
- Refresh with `qs -c noctalia-shell ipc call plugin:arch-updater refresh`
- Update with `qs -c noctalia-shell ipc call plugin:arch-updater update`

**Launcher Integration**
- Refresh with `>au-refresh`
- Update with `>au-update`

**Control Center Widget**
- Open panel

## Configuration
Settings UI allows for editing commands and changing toggles

## Requirements
- The default commands require `paru`, `checkupdates`, `flatpak` and `ghostty` but you can edit them
- Designed for Arch, although commands can be edited so it may be possible to make it work on other distros
- CPU (Optional)

### Note:
This is my first QML project so I apologize for any sloppy code
