# Hyprland Module

This module owns the Hyprland compositor config, the Hyprland-specific
`systemd --user` startup graph, and the managed monitor/workspace routing under
`~/.config/hypr/conf.d/92-monitors.conf`.

## Responsibilities

- install the Hyprland config split under `~/.config/hypr`
- install the canonical Hypr session environment file
- install the managed monitor/workspace mapping for this host
- define the Hyprland session targets and services under `~/.config/systemd/user`

This module does not install the system-wide display-manager session entry
anymore. That belongs to the `gdm` and `sessions` modules.

## Entry points

- GDM launches `modules/gdm/dotfiles/hyprland-optimized-session`.
- The wrapper only pre-warms `systemd --user` with the static Hyprland session
  identity and then executes `start-hyprland` or `Hyprland`.
- Once Hyprland is up, `dotfiles/hypr/hyprland.conf` runs:
  `exec-once = ~/.local/bin/hypr-session-init`.
- `hypr-session-init` is now the compositor-side entrypoint that imports the
  live Wayland/session variables and starts `hyprland-session.target`.

## Startup flow

1. GDM starts `hyprland-optimized-session`.
2. The wrapper exports `DESKTOP_SESSION=Hyprland`,
   `XDG_SESSION_DESKTOP=Hyprland`, `XDG_CURRENT_DESKTOP=Hyprland`,
   `XDG_SESSION_TYPE=wayland`, `GTK_USE_PORTAL=1`, and `SYSTEMD_OFFLINE=0`.
3. The wrapper preloads those values into `systemd --user` with
   `systemctl --user set-environment`.
4. The wrapper executes `start-hyprland` or falls back to `Hyprland`.
5. Hyprland reads `~/.config/hypr/hyprland.conf` and runs
   `~/.local/bin/hypr-session-init`.
6. `hypr-session-init` loads `~/.config/environment.d/10-hyprland.conf`,
   normalizes `PATH` and XDG paths, detects `WAYLAND_DISPLAY` and
   `HYPRLAND_INSTANCE_SIGNATURE`, imports the live environment into
   `systemd --user` and DBus, and starts `hyprland-session.target`.
7. `hyprland-session.target` pulls in:
   `graphical-session.target`, `graphical-session-pre.target`,
   `xdg-desktop-autostart.target`, `hypr-bootstrap.service`, and
   `hypr-daemons.target`.
8. `hypr-bootstrap.service` runs `~/.local/bin/hypr-bootstrap` as the early
   oneshot stage.
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
  Early oneshot bootstrap. Runs `hypr-osc switch --no-notify` and
  `osc-soundctl init`.
- `hypr-daemons.target`
  Explicit daemon stage. It now declares the core Hyprland services it wants.
- `hypr-post-bootstrap.service`
  Late oneshot polish. Runs `osc-shell ensure`, applies cursor sync with
  `hyprctl setcursor`, and starts `xdg-desktop-portal-delayed.service` when the
  unit exists. It is ordered after the daemon services rather than after the
  target itself to avoid systemd ordering cycles.

Daemon-stage units started by `hypr-daemons.target`:

- `hyprland-polkit-agent.service`
  Runs `polkit-gnome-authentication-agent-1`.
- `hypr-nm-applet.service`
  Runs `nm-applet --indicator`.
- `hypr-blueman-applet.service`
  Runs `blueman-applet`.
- `hypr-clip-persist.service`
  Runs `wl-clip-persist --clipboard both`.
- `gnome-keyring-secrets.service`
  Runs `gnome-keyring-daemon --components=secrets,pkcs11`.

## Config layout

- `dotfiles/hypr/hyprland.conf`
  Minimal root config that sources the split files and starts
  `hypr-session-init`.
- `dotfiles/environment.d/10-hyprland.conf`
  Shared source of truth for session environment values.
- `dotfiles/hypr/conf.d/92-monitors.conf`
  Repo-managed monitor layout and workspace routing for the current setup.

## Conditions and notes

- Most Hyprland units require `WAYLAND_DISPLAY` and
  `XDG_CURRENT_DESKTOP=Hyprland`.
- Shared XDG autostart masks for `nm-applet`, `blueman`, and keyring desktop
  entries live in the `wayland-autostart` module.
- The systemd graph is intentionally split into `bootstrap -> daemons ->
  post-bootstrap` so ordering remains visible in unit files rather than hidden
  in shell scripts.
