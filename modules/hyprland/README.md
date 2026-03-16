# Hyprland Module

This module owns the Hyprland compositor config, the Hyprland-specific
`systemd --user` startup graph, and the managed monitor/workspace routing under
`~/.config/hypr/conf.d/70-monitors.conf`.

## Responsibilities

- install the Hyprland config split under `~/.config/hypr`
- install the canonical Hypr session environment file
- install the managed monitor/workspace mapping for this host
- define the Hyprland session targets and services under `~/.config/systemd/user`
- run a post-install hook that renders theme files, removes the
  Hyprland-only keyring override, re-enables the stock GDM/PAM-managed
  `gnome-keyring-daemon` units, and persists the Blueman plugin mask

This module does not install the system-wide display-manager session entry
anymore. That belongs to the `gdm` and `sessions` modules.

## Entry points

- GDM launches `modules/gdm/dotfiles/hyprland-optimized-session`.
- The wrapper consumes `~/.config/environment.d/10-hyprland.conf` through the
  shared `hypr-session-common` helper when available, pre-warms
  `systemd --user` with the static Hyprland session environment, and then
  executes `start-hyprland` or `Hyprland`.
- Once Hyprland is up, `dotfiles/hypr/hyprland.conf` runs:
  `exec-once = ~/.local/bin/hypr-session-init`.
- `hypr-session-init` is now the compositor-side entrypoint that imports the
  live Wayland/session variables and starts `hyprland-session.target`.

## Startup flow

1. GDM starts `hyprland-optimized-session`.
2. The wrapper loads the canonical Hyprland environment file through
   `hypr-session-common`, normalizes path variables, applies the static session
   identity, and preloads those values into `systemd --user`.
3. The wrapper executes `start-hyprland` or falls back to `Hyprland`.
4. Hyprland reads `~/.config/hypr/hyprland.conf` and runs
   `~/.local/bin/hypr-session-init`.
5. `hypr-session-init` loads `~/.config/environment.d/10-hyprland.conf`,
   normalizes `PATH` and XDG paths, detects `WAYLAND_DISPLAY` and
   `HYPRLAND_INSTANCE_SIGNATURE`, imports the live environment into
   `systemd --user` and DBus, and starts `hyprland-session.target`.
6. `hyprland-session.target` pulls in:
   `graphical-session.target`, `graphical-session-pre.target`,
   `xdg-desktop-autostart.target`, `hypr-bootstrap.service`,
   `hypr-audio-init.service`, and
   `hypr-daemons.target`.
7. `hypr-bootstrap.service` runs `~/.local/bin/hypr-bootstrap` as the early
   oneshot stage.
8. `hypr-audio-init.service` runs `osc-soundctl init` as a separate
   non-blocking-ish oneshot so monitor/workspace normalization is not coupled to
   audio setup.
9. `hypr-daemons.target` becomes the daemon stage. It explicitly wants the
   long-running Hypr helpers.
10. `hypr-post-bootstrap.service` is started by `hyprland-session.target` and
    runs after the daemon services it depends on, performing the final cursor,
    shell, and portal polish.

## Session graph

Core session units:

- `hyprland-session.target`
  Session umbrella target started by `hypr-session-init`.
- `hypr-bootstrap.service`
  Early oneshot bootstrap. Runs `hypr-osc switch --no-notify`.
- `hypr-audio-init.service`
  Separate oneshot audio initialization. Runs `osc-soundctl init` after the
  bootstrap stage.
- `hypr-daemons.target`
  Explicit daemon stage. It now declares the core Hyprland services it wants.
- `hypr-post-bootstrap.service`
  Late oneshot polish. Runs `osc-shell ensure`, applies cursor sync with
  `hyprctl setcursor`, and starts `hyprsunset.service`, `noctalia.service`,
  and `xdg-desktop-portal-delayed.service` when those units exist. It is
  ordered after the daemon services rather than after the target itself to
  avoid systemd ordering cycles.

Daemon-stage units started by `hypr-daemons.target`:

- `hyprland-polkit-agent.service`
  Runs `polkit-gnome-authentication-agent-1`.
- `hypr-nm-applet.service`
  Runs `nm-applet --indicator`.
- `hypr-blueman-applet.service`
  Runs `blueman-applet` after disabling Blueman plugins that race on OBEX
  agent ownership.
- `hypr-clip-persist.service`
  Runs `wl-clip-persist --clipboard both`.

## Config layout

- `dotfiles/hypr/hyprland.conf`
  Minimal root config that sources the split files and starts
  `hypr-session-init`.
- `dotfiles/hypr/conf.d/20-theme.conf`
  Generated Hyprland theme file derived from `theme/theme.env`. Contains the
  palette plus the visual assignments for borders, blur, shadow, opacity,
  groupbars, compositor background, workspace chrome exceptions, and Hyprland
  theme string values used by binds.
- `dotfiles/environment.d/10-hyprland.conf`
  Generated session environment file derived from `theme/theme.env` plus the
  fixed Hyprland session defaults.
- `theme/theme.env`
  Canonical theme manifest for GTK theme, cursor/icon theme, Catppuccin accent,
  and Hyprland visual sizing.
- `scripts/render-theme.sh`
  Renderer that regenerates `10-hyprland.conf` and `20-theme.conf` from
  `theme/theme.env`.
- `scripts/install.sh`
  Post-install hook that renders the theme files, removes the Hyprland-only
  keyring override, re-enables the stock `gnome-keyring-daemon` units, and
  persists the Blueman plugin mask.
- `dotfiles/hypr/conf.d/70-monitors.conf`
  Repo-managed, host-specific monitor layout and workspace routing for the
  current setup.

## Conditions and notes

- Most Hyprland units require `WAYLAND_DISPLAY` and
  `XDG_CURRENT_DESKTOP=Hyprland`.
- Shared XDG autostart masks for `nm-applet`, `blueman`, and keyring desktop
  entries live in the `wayland-autostart` module.
- The systemd graph is intentionally split into `bootstrap -> daemons ->
  post-bootstrap` so ordering remains visible in unit files rather than hidden
  in shell scripts.
- The monitor routing file is intentionally host-specific; this module no
  longer claims to be a portable multi-host monitor profile.
