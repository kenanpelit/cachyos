# Fastfetch

This module owns the portable `fastfetch` preset installed to
`~/.config/fastfetch/config.jsonc`.

## Goals

- stay portable across shells, compositors, and terminals
- avoid machine-specific asset paths
- surface the information that is actually useful on this setup
- keep the output compact enough for daily terminal use

## Design

- Uses the built-in `cachyos` logo instead of a wallpaper path, so the preset
  works on any machine without extra assets.
- Splits the output into three sections:
  - `System`
  - `Session`
  - `Hardware`
- Prefers stable modules over fragile ones:
  - keeps `wm`, theme, icons, cursor, and font
  - avoids `de` because standalone compositors like Mango/Niri/Hyprland often
    do not expose a DE
  - avoids `terminalfont` because `kitty` detection is not reliable here
  - avoids `localip` because it is noisy on this setup
- Uses IEC units with one decimal place so memory and disk output stay readable.

## Validation

Validate the preset with:

```bash
fastfetch --config ~/.config/fastfetch/config.jsonc
```

Or directly from the repo:

```bash
fastfetch --config modules/fastfetch/dotfiles/fastfetch/config.jsonc
```
