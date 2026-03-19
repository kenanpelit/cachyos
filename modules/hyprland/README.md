# Hyprland Module

This module owns the Hyprland compositor config, the Hyprland-specific
`systemd --user` startup graph, and the managed monitor/workspace routing under
`~/.config/hypr/conf.d/70-monitors.conf`.

## Responsibilities

- install the Hyprland config split under `~/.config/hypr`
- install the canonical Hypr session environment file
- make the Hyprland UWSM wrapper consume the curated repo-managed
  environment stack before the compositor starts
- install the managed monitor/workspace mapping for this host
- define the Hyprland session targets and services under `~/.config/systemd/user`
- run a post-install hook that renders theme files, removes the
  Hyprland-only keyring override, re-enables the stock GDM/PAM-managed
  `gnome-keyring-daemon` units, reloads user units, and persists the Blueman
  plugin mask

This module does not install the system-wide display-manager session entry
anymore. That belongs to the `sessions` module and the selected display-manager
module.

## Entry points

- The `sessions` module now installs a single Hyprland session entry:
  `modules/hyprland/dotfiles/hyprland-uwsm.desktop`.
- That desktop entry launches
  `modules/sessions/dotfiles/hyprland-uwsm-session`.
- TTY login now reuses the same UWSM session path via
  `osc-tty-launcher auto-tty` from `~/.zprofile`, so TTY2 and any display
  manager session entry both enter
  Hyprland through the same wrapper/session identity.
- The wrapper loads the curated Hyprland environment stack through
  `hypr-session-common` (`10-gtk.conf`, `10-hyprland.conf`, `20-qt.conf`,
  `30-ollama.conf`, and `99-dms-icons.conf` when present), applies the
  Hyprland session identity
  (`DESKTOP_SESSION=hyprland-uwsm`, `XDG_CURRENT_DESKTOP=Hyprland`), and then
  hands off to `uwsm start`.
- Once Hyprland is up, `dotfiles/hypr/hyprland.conf` runs:
  `exec-once = ~/.local/bin/hypr-session-init`.
- `hypr-session-init` is now the compositor-side entrypoint that starts
  `hyprland-session.target`. Under UWSM it trusts the pre-finalized session
  environment and only falls back to runtime detection/sync if
  `WAYLAND_DISPLAY` or `HYPRLAND_INSTANCE_SIGNATURE` are unexpectedly missing.
  Outside UWSM it retains the older full env-sync path as a compatibility
  fallback.

## Startup flow

1. A display manager session entry or the TTY launcher starts
   `hyprland-uwsm-session`.
2. The wrapper loads the curated Hyprland environment stack, applies the
   Hyprland UWSM session identity, and executes `uwsm start -- start-hyprland`
   (or `Hyprland` if `start-hyprland` is unavailable).
3. UWSM creates the compositor service, waits for readiness variables, and
   finalizes the session environment for the user manager.
4. Hyprland reads `~/.config/hypr/hyprland.conf` and runs
   `~/.local/bin/hypr-session-init`.
5. If the session is UWSM-managed, `hypr-session-init` starts
   `hyprland-session.target` immediately and only performs runtime
   detection/sync as a fallback when UWSM did not finalize
   `WAYLAND_DISPLAY` or `HYPRLAND_INSTANCE_SIGNATURE`. If UWSM is not
   present, the script falls back to the older full `environment.d` import
   path.
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
    runs after the daemon stage, performing final cursor and session polish.

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
  Late oneshot polish. Applies cursor sync with `hyprctl setcursor` and keeps
  post-start session tweaks separate from the daemon stage. Long-running shell,
  night-light, and delayed portal units are started by systemd directly rather
  than manually from this script.

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
- Hypr-only daemon-stage services are now lifecycle-bound directly to
  `wayland-wm@start\x2dhyprland.service` via `BindsTo=`/`After=` so they are
  torn down immediately if the compositor dies unexpectedly.

## Config layout

- `dotfiles/hypr/hyprland.conf`
  Minimal root config that sources the split files and starts
  `hypr-session-init`.
- `dotfiles/hypr/conf.d/20-theme.conf`
  Generated Hyprland theme file derived from `theme/theme.env`. Contains the
  palette plus the visual assignments for borders, blur, shadow, opacity,
  groupbars, compositor background, workspace chrome exceptions, and Hyprland
  theme string values used by binds.
- `dotfiles/hypr/conf.d/40-rules.conf`
  Window behavior and app-placement policy. Pure numbered workspace placement
  rules are now centralized in a dedicated anonymous `windowrule = ...`
  section using the current Hyprland syntax, while mixed float/size/dialog
  rules remain named blocks so they can still be inspected and toggled
  individually.
- `dotfiles/environment.d/10-hyprland.conf`
  Generated session environment file derived from `theme/theme.env` plus the
  Hyprland-specific session defaults. Session identity such as
  `DESKTOP_SESSION=hyprland-uwsm` is now owned by the UWSM wrapper rather than
  this file.
- `theme/theme.env`
  Canonical theme manifest for GTK theme, cursor/icon theme, Catppuccin accent,
  and Hyprland visual sizing.
- `scripts/render-theme.sh`
  Renderer that regenerates `10-hyprland.conf` and `20-theme.conf` from
  `theme/theme.env`. `render-theme.sh --check` verifies that the generated
  files are still in sync with the manifest.
- `modules/sessions/dotfiles/hyprland-uwsm-session`
  UWSM-first wrapper. Loads the repo-managed `environment.d` stack and then
  enters `uwsm start`.
- `scripts/install.sh`
  Post-install hook that renders the theme files, removes the Hyprland-only
  keyring override, re-enables the stock `gnome-keyring-daemon` units, and
  persists the Blueman plugin mask.
- `dotfiles/hypr/conf.d/70-monitors.conf`
  Repo-managed, host-specific monitor layout and workspace routing for the
  current setup.
- `dotfiles/systemd/user/xdg-desktop-portal-gnome.service.d/10-hyprland.conf`
  and `dotfiles/systemd/user/xdg-desktop-portal-gtk.service.d/10-hyprland.conf`
  Unset `GDK_BACKEND` for the GTK/GNOME portal services so the Hyprland
  session-wide override does not leak into portal processes.

## Conditions and notes

- Most Hyprland units require `WAYLAND_DISPLAY` and
  `XDG_CURRENT_DESKTOP=Hyprland`.
- The repo-managed `~/.config/environment.d/*.conf` stack is the canonical
  source for Hyprland session variables under UWSM, but it is consumed through
  a curated Hyprland-specific allowlist so Niri-only or ad-hoc user overrides
  do not leak into the Hyprland session wrapper. `hypr-session-init` avoids
  re-importing that full static environment when UWSM is already managing the
  session and only backfills missing compositor runtime variables as a safety
  net. When that fallback path is used, it emits a warning to the journal so
  session drift is visible.
- Qt theming authority is intentionally split: `modules/qt/dotfiles/environment.d/20-qt.conf`
  owns `QT_QPA_PLATFORMTHEME`, `QT_QPA_PLATFORMTHEME_QT6`, and
  `QT_STYLE_OVERRIDE`, while the Hyprland session layer only keeps generic Qt
  Wayland/scaling hints. `99-dms-icons.conf` now only reinforces icon-theme
  variables and no longer overrides the Qt platform theme.
- Logout flows should prefer `uwsm stop` over `hyprctl dispatch exit` so the
  compositor, session targets, and UWSM-managed user services shut down
  together.
- `Ctrl+Alt+BackSpace` is reserved as an emergency exit key and runs
  `uwsm stop` directly.
- Shared XDG autostart masks for `nm-applet`, `blueman`, and keyring desktop
  entries live in the `wayland-autostart` module.
- The Hyprland session owns the polkit agent. Keep Noctalia's `polkit-agent`
  plugin disabled to avoid duplicate authentication agents.
- Selected long-lived GUI launch keybinds use `uwsm app -a ... --` so app
  scopes and journal entries carry stable names instead of anonymous
  compositor-child processes.
- The UWSM session fallback path intentionally keeps a minimal default `PATH`;
  personal helper directories such as `.iptv/bin`, zinit shims, and GOPATH
  bins are no longer injected into the desktop session bootstrap.
- The systemd graph is intentionally split into `bootstrap -> daemons ->
  post-bootstrap` so ordering remains visible in unit files rather than hidden
  in shell scripts.
- The monitor routing file is intentionally host-specific; this module no
  longer claims to be a portable multi-host monitor profile.
- Persistent workspace ownership stays in `70-monitors.conf`; `40-rules.conf`
  only handles per-application placement. The module intentionally does not
  translate app placement into `workspace = ..., on-created-empty:...` rules,
  because that would couple app launch behavior to persistent workspace
  creation and can auto-spawn apps during session startup.
