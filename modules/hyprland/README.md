# Hyprland Module

This module owns the Hyprland compositor config, the Hyprland-specific
`systemd --user` startup graph, and the managed monitor/workspace routing under
`~/.config/hypr/conf.d/70-monitors.conf`.

## Responsibilities

- install the Hyprland config split under `~/.config/hypr`
- install the canonical Hypr session environment file
- install the ordered Hypr session env allowlist manifest
- make the Hyprland UWSM wrapper consume the curated repo-managed
  environment stack before the compositor starts
- render the managed monitor/workspace mapping from a selected monitor profile
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
  `modules/sessions/dotfiles/hyprland-uwsm.desktop`.
- That desktop entry launches
  `modules/sessions/dotfiles/hyprland-uwsm-session`.
- TTY login now reuses the same UWSM session path via
  `osc-tty-launcher auto-tty` from `~/.zprofile`, so TTY2 and any display
  manager session entry both enter
  Hyprland through the same wrapper/session identity.
- The wrapper loads the curated Hyprland environment stack through
  `hypr-session-common` plus the ordered allowlist manifest at
  `~/.config/environment.d/hyprland-session.envlist`, normalizes path
  variables, applies the Hyprland session identity
  (`DESKTOP_SESSION=hyprland-uwsm`, `XDG_CURRENT_DESKTOP=Hyprland`), and then
  hands off to `uwsm start`.
- Once Hyprland is up, the repo-managed drop-in for
  `wayland-wm@start\x2dhyprland.service` starts `hyprland-session.target` with
  `ExecStartPost=` once the compositor service is ready.
- `hypr-session-init` remains available as a manual compatibility helper for
  runtime env backfill and emergency target restarts. Under UWSM it trusts the
  pre-finalized session environment and only falls back to runtime
  detection/sync if `WAYLAND_DISPLAY` or `HYPRLAND_INSTANCE_SIGNATURE` are
  unexpectedly missing. Outside UWSM it retains the older full env-sync path as
  a compatibility fallback.

## Startup flow

1. A display manager session entry or the TTY launcher starts
   `hyprland-uwsm-session`.
2. The wrapper loads the curated Hyprland environment stack, applies the
   Hyprland UWSM session identity, normalizes paths, and executes
   `uwsm start -- start-hyprland` (or `Hyprland` if `start-hyprland` is
   unavailable).
3. UWSM creates the compositor service, waits for readiness variables, and
   finalizes the session environment for the user manager.
4. The repo-managed drop-in for `wayland-wm@start\x2dhyprland.service` starts
   `hyprland-session.target` with `ExecStartPost=` once Hyprland is actually
   running.
5. `hyprland-session.target` pulls in:
   `graphical-session.target`, `xdg-desktop-autostart.target`,
   `hypr-session-env.service`, `hypr-bootstrap.service`,
   `hypr-audio-init.service`,
   `hypr-shell-ensure.service`,
   `hypr-daemons.target`, and `hypr-post-daemons.target`.
6. `hypr-session-env.service` runs `hypr-session-init --no-start-target`
   before the rest of the Hyprland graph so `systemd --user` sees
   `WAYLAND_DISPLAY` and `HYPRLAND_INSTANCE_SIGNATURE` before late units are
   evaluated.
7. `hypr-bootstrap.service` runs `~/.local/bin/hypr-bootstrap` as the early
   oneshot stage.
8. `hypr-audio-init.service` runs `osc-soundctl init` as a separate
   non-blocking-ish oneshot so monitor/workspace normalization is not coupled to
   audio setup.
9. `hypr-shell-ensure.service` runs `osc-shell ensure` as a compositor-neutral
   shell bootstrap before tray readiness is checked.
10. `hypr-daemons.target` becomes the daemon stage. It explicitly wants the
    long-running Hypr helpers.
11. `hypr-post-daemons.target` becomes the ordered late stage; the enabled
    desktop-settings and post-bootstrap oneshots are pulled in there.
12. `hypr-desktop-settings.service` runs after the daemon stage and applies the
    dconf/GSettings desktop theme sync as a tracked oneshot.
13. `hypr-post-bootstrap.service` then runs after the daemon and desktop
    settings stages, performing final cursor polish.

## Session graph

Core session units:

- `hyprland-session.target`
  Session umbrella target started by the compositor service lifecycle drop-in.
- `hypr-session-env.service`
  Pre-bootstrap runtime env sync. Runs `hypr-session-init --no-start-target`
  so the user manager sees the finalized Hyprland runtime variables before the
  rest of the session units are evaluated.
- `hypr-bootstrap.service`
  Early oneshot bootstrap. Runs `hypr-session-route --no-notify`.
- `hypr-audio-init.service`
  Separate oneshot audio initialization. Runs `osc-soundctl init` after the
  bootstrap stage.
- `hypr-shell-ensure.service`
  One-shot shell backend ensure stage. Runs `osc-shell ensure` before the tray
  readiness gate so Noctalia/DMS shell IPC is present deterministically.
- `hypr-daemons.target`
  Explicit daemon stage. It now declares the core Hyprland services it wants.
- `hypr-status-notifier-ready.service`
  Shell-neutral readiness gate that waits for `org.kde.StatusNotifierWatcher`
  before tray applets such as NetworkManager and Blueman start.
- `hypr-desktop-settings.service`
  Tracked oneshot desktop settings sync. Applies GTK/icon/cursor preferences
  after the daemon stage instead of backgrounding a detached shell job.
- `hypr-post-bootstrap.service`
  Late oneshot polish. Applies cursor sync with `hyprctl setcursor` and keeps
  final compositor tweaks separate from the daemon and desktop-settings stages.
  Long-running shell, night-light, and delayed portal units are started by
  systemd directly rather than manually from this script.

Daemon-stage units started by `hypr-daemons.target`:

- `hyprland-polkit-agent.service`
  Runs `polkit-gnome-authentication-agent-1`.
- `hypr-nm-applet.service`
  Runs `nm-applet --indicator` after the explicit status-notifier readiness
  gate.
- `hypr-blueman-applet.service`
  Runs `blueman-applet` after disabling Blueman plugins that race on OBEX
  agent ownership and after the explicit status-notifier readiness gate.
- `hypr-clip-persist.service`
  Runs `wl-clip-persist --clipboard both`.
- Hypr-only daemon-stage services are now lifecycle-bound directly to
  `wayland-wm@start\x2dhyprland.service` via `BindsTo=`/`After=` so they are
  torn down immediately if the compositor dies unexpectedly.

## Config layout

- `dotfiles/hypr/hyprland.conf`
  Minimal root config that sources the split files; session-target startup is
  now owned by the compositor service lifecycle drop-in rather than Hyprland
  `exec-once`.
- `dotfiles/hypr/conf.d/20-theme.conf`
  Generated Hyprland theme file derived from `theme/theme.env`. Contains the
  palette plus the visual assignments for borders, blur, shadow, opacity,
  groupbars, compositor background, workspace chrome exceptions, and Hyprland
  theme string values used by binds.
- `dotfiles/hypr/conf.d/rules/*.conf`
  Window rules are split by concern (`core`, `workspace-routing`, `floating`,
  `dialogs`, `theme-overrides`) and indexed by `40-rules.conf`.
- `dotfiles/hypr/conf.d/binds/*.conf`
  Keybinds are split by concern (`navigation`, `shell-session`, `apps`,
  `workspaces`, `monitors-hardware`) and indexed by `50-binds.conf`.
- `dotfiles/hypr/conf.d/40-rules.conf`
  Window-rule index that sources the topic-specific rules files.
- `dotfiles/environment.d/10-hyprland.conf`
  Generated session environment file derived from `theme/theme.env` plus the
  Hyprland-specific session defaults. Session identity such as
  `DESKTOP_SESSION=hyprland-uwsm` is now owned by the UWSM wrapper rather than
  this file, and it is installed under
  `~/.config/session-env/hyprland/10-hyprland.conf`.
- `dotfiles/environment.d/hyprland-session.envlist`
  Ordered allowlist manifest for the Hyprland session wrapper. This keeps the
  session env stack data-driven instead of hard-coding file names in shell.
- `theme/theme.env`
  Canonical theme manifest for GTK theme, cursor/icon theme, Catppuccin accent,
  and Hyprland visual sizing.
- `scripts/render-theme.sh`
  Renderer that regenerates `10-hyprland.conf` and `20-theme.conf` from
  `theme/theme.env`. `render-theme.sh --check` verifies that the generated
  files are still in sync with the manifest.
- `monitors/profile.env` and `monitors/profiles/*.conf`
  Canonical monitor-profile selection plus the available monitor/workspace
  layouts (`desk`, `mobile`, `single-external`).
- `scripts/render-monitors.sh`
  Renderer that regenerates `70-monitors.conf` from the selected monitor
  profile. `render-monitors.sh --check` verifies that the generated file is in
  sync with the manifest and selected profile.
- `modules/sessions/dotfiles/hyprland-uwsm-session`
  UWSM-first wrapper. Loads the repo-managed shared `environment.d` stack
  including `00-wayland.conf`, plus the Hyprland-only session file, normalizes
  path variables, clears foreign compositor variables, and then enters
  `uwsm start`.
- `scripts/install.sh`
  Post-install hook that renders the theme and monitor files, removes the
  Hyprland-only keyring override, re-enables the stock
  `gnome-keyring-daemon` units, and persists the Blueman plugin mask.
- `dotfiles/hypr/conf.d/70-monitors.conf`
  Generated monitor layout and workspace routing for the selected monitor
  profile.
- `dotfiles/systemd/user/xdg-desktop-portal-gnome.service.d/10-hyprland.conf`
  and `dotfiles/systemd/user/xdg-desktop-portal-gtk.service.d/10-hyprland.conf`
  Unset `GDK_BACKEND` for the GTK/GNOME portal services so the Hyprland
  session-wide override does not leak into portal processes.

## Conditions and notes

- Most Hyprland units require `WAYLAND_DISPLAY` and
  `XDG_CURRENT_DESKTOP=Hyprland`.
- The repo-managed `~/.config/environment.d/*.conf` stack remains the shared
  base layer. `modules/wayland-env/dotfiles/environment.d/00-wayland.conf`
  owns compositor-agnostic Wayland toolkit/runtime hints, while Hyprland-only
  variables now live in
  `~/.config/session-env/hyprland/10-hyprland.conf`. The ordered
  `hyprland-session.envlist` allowlist keeps Niri-only or ad-hoc user
  overrides from leaking into the Hyprland session wrapper.
  `hypr-session-init` remains available as a manual compatibility helper and
  avoids re-importing that full static environment when UWSM is already
  managing the session, only backfilling missing compositor runtime variables
  as a safety net. When that fallback path is used, it emits a warning to the
  journal so session drift is visible.
- Hyprland and Niri now share a common Wayland bootstrap helper for env-file
  parsing, path normalization, `WAYLAND_DISPLAY` detection, and
  systemd/dbus environment sync. Compositor-specific helpers keep only the
  runtime detection logic that is unique to each compositor.
- Qt theming authority is intentionally split: `modules/qt/dotfiles/environment.d/20-qt.conf`
  owns `QT_QPA_PLATFORMTHEME`, `QT_QPA_PLATFORMTHEME_QT6`, and
  `QT_STYLE_OVERRIDE`, while the Hyprland session layer only keeps generic Qt
  Wayland/scaling hints. `99-dms-icons.conf` now only reinforces icon-theme
  variables and no longer overrides the Qt platform theme.
- The generated Hyprland env file now exposes both `PATH_CORE` and `PATH_USER`
  alongside the combined `PATH` so desktop bootstrap path policy stays visible
  instead of being buried in shell code.
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
  desktop-settings -> post-bootstrap` so ordering remains visible in unit files
  rather than hidden in shell scripts.
- The monitor routing file is generated from a selected profile rather than
  being edited in place; use `monitors/profile.env` to switch profiles.
- Persistent workspace ownership stays in `70-monitors.conf`; `40-rules.conf`
  only handles per-application placement. The module intentionally does not
  translate app placement into `workspace = ..., on-created-empty:...` rules,
  because that would couple app launch behavior to persistent workspace
  creation and can auto-spawn apps during session startup.
