# Niri Module

This module owns the Niri compositor config, the Niri-specific
`systemd --user` startup graph, and the curated environment stack used by the
UWSM-first session wrapper.

## Entry points

- The `sessions` module now installs a single Niri session entry:
  `modules/sessions/dotfiles/niri-uwsm.desktop`.
- That desktop entry launches `modules/sessions/dotfiles/niri-uwsm-session`.
- TTY login now reuses the same UWSM session path via
  `osc-tty-launcher auto-tty` from `~/.zprofile`, so TTY3 and any display
  manager session entry both enter
  Niri through the same wrapper/session identity.
- The wrapper loads the curated Niri environment stack through
  `niri-session-common` and the manifest
  `~/.config/environment.d/niri-session.envlist`, which now starts with the
  shared Wayland layer at `~/.config/environment.d/00-wayland.conf`, includes
  the shared GTK/Qt layers, optionally includes repo-managed overlays such as
  `30-ollama.conf` when present, and explicitly includes the Niri-only session
  file at `~/.config/session-env/niri/10-niri-env.conf`,
  normalizes path variables, applies the Niri session identity
  (`DESKTOP_SESSION=niri-uwsm`, `XDG_CURRENT_DESKTOP=niri`), clears foreign
  compositor variables, and then hands off to `uwsm start -- niri-session`.
- Every unit shipped under `dotfiles/systemd/user/` is linked/enabled by the
  `user-services` module when `niri` is enabled in `hosts/*.yaml`.

## Startup flow

1. A display manager session entry or the TTY launcher starts
   `niri-uwsm-session`.
2. The wrapper loads the curated Niri environment stack, normalizes paths,
   applies the Niri UWSM session identity, and executes `uwsm start -- niri-session`
   (or `niri` if `niri-session` is unavailable).
3. UWSM creates the compositor service, waits for `NIRI_SOCKET`, and finalizes
   the session environment for the user manager.
4. The repo-managed drop-in for `wayland-wm@niri\x2dsession.service` starts
   `niri-session.target` with `ExecStartPost=` once the compositor is ready.
5. `niri-session.target` pulls in `graphical-session.target`,
   `xdg-desktop-autostart.target`, `niri-session-env.service`, `niri-bootstrap.service`,
   `niri-shell-ensure.service`, `niri-daemons.target`,
   `niri-post-daemons.target`, and the shared
   compositor-session units enabled by other modules.
6. `niri-session-env.service` runs `niri-session-init --no-start-target` before
   the rest of the session graph so `systemd --user` gets `NIRI_SOCKET` and the
   finalized runtime vars even when UWSM finalize timing is late.
7. `niri-bootstrap.service` runs `~/.local/bin/niri-bootstrap`, which now uses
   the shared Niri session helper for runtime env/socket detection before
   calling `niri-osc set init`.
8. `niri-shell-ensure.service` runs `osc-shell ensure` under `systemd --user`
   instead of relying on `spawn-at-startup` in `config.kdl`.
9. `niri-daemons.target` becomes the daemon stage for long-running helpers.
10. `niri-post-daemons.target` becomes the ordered late stage after
   `niri-daemons.target`.
11. `niri-post-bootstrap.service` runs `~/.local/bin/niri-post-bootstrap` after
    the daemon services it depends on and performs the GNOME desktop settings
    sync before emitting the ready notification.

## What starts during session startup

These units make up the core Niri session chain:

- `niri-session.target`
  Session umbrella target started by the UWSM compositor service drop-in.
- `niri-session-env.service`
  Pre-bootstrap runtime env sync. Runs `niri-session-init --no-start-target`
  so the user manager sees `NIRI_SOCKET` before condition-gated units are
  evaluated.
- `niri-bootstrap.service`
  Early oneshot bootstrap. Uses the shared Niri session helper to normalize
  runtime state and then runs `niri-osc set init`.
- `niri-shell-ensure.service`
  Starts the shell backend through `osc-shell ensure` under `systemd --user`.
- `niri-daemons.target`
  Explicit daemon stage. It now declares the core Niri services it wants.
- `niri-post-daemons.target`
  Ordered late stage for session polish and optional post-daemon services.
- `niri-post-bootstrap.service`
  Late oneshot polish. Runs the desktop theme/icon/cursor sync and then sends
  a best-effort "Session ready" notification after the daemon stage completes.
- `niri-status-notifier-ready.service`
  Waits for a session `StatusNotifierWatcher` before tray applets such as
  Blueman start.

These services belong to `niri-daemons.target` and normally come up with the
session once the environment conditions are satisfied:

- `niri-polkit-agent.service`
  Runs `polkit-gnome-authentication-agent-1`. The Niri session now owns the
  polkit agent directly, independent of the selected shell backend.
- `niri-nm-applet.service`
  Runs `nm-applet --indicator`.
- `niri-blueman-applet.service`
  Runs `blueman-applet` after the explicit status-notifier readiness gate.
- `niri-snapper-tools-check.service`
  Runs the snapshot boot check for `snapper-tools`.
- `niri-sticky.service`
  Runs `niri-float-sticky daemon` for floating sticky windows across workspaces.
- `niri-niriswitcher.service`
  Runs `niriswitcher`.
- Niri-only daemon-stage services are now lifecycle-bound directly to
  `wayland-wm@niri\x2dsession.service` via `BindsTo=`/`After=` so they stop
  immediately if the compositor dies unexpectedly.

The shared `clipse.service` now belongs to the standalone `clipse` module and
is bound to `graphical-session.target`, so both Niri and Hyprland reuse the
same clipboard listener unit.

The `sunsetr` module is now shared across the Hyprland and Niri Wayland
sessions and hooks into the shared `graphical-session.target`:

- `sunsetr.service`
  Runs from `graphical-session.target` during supported Wayland sessions.
- `sunsetr-auto-profile.timer`
  Applies the scheduled preset map after startup and at each declared schedule
  boundary while the graphical Wayland session is active.

## Shared session timers

These delayed timers are now owned by the `sessions` module because they are
graphical-session-scoped helpers rather than Niri-specific daemons:

- `geoclue-agent.timer`
  Starts `geoclue-agent.service` 15 seconds after the graphical session
  becomes active.
- `ppp-auto-profile.timer`
  Starts `ppp-auto-profile.service` 30 seconds after the graphical session
  becomes active and then reruns every 15 seconds.

## Conditions and notes

- The daemon-stage Niri services generally require `WAYLAND_DISPLAY` and
  `XDG_CURRENT_DESKTOP=niri`.
- Units that need deterministic compositor readiness now also require
  `NIRI_SOCKET`.
- The repo-managed `~/.config/environment.d/*.conf` stack remains the shared
  base layer. `modules/wayland-env/dotfiles/environment.d/00-wayland.conf`
  owns compositor-agnostic Wayland toolkit/runtime hints, while Niri-only variables live in
  `~/.config/session-env/niri/10-niri-env.conf` and are consumed through the
  curated Niri-specific allowlist manifest so compositor-specific overrides do
  not leak across sessions. Optional manifest entries are skipped cleanly, while
  missing required entries now emit a warning instead of failing silently.
  `niri-session-init` remains available as a manual compatibility helper and
  only backfills missing compositor runtime variables when UWSM did not
  finalize them.
- The shared `xdg-portal` module now owns the Niri portal preference file:
  generic dialogs/settings stay on GTK, screencast/screenshot stay on `gnome`,
  and `RemoteDesktop` stays on GNOME as the only installed backend in this
  repo that actually advertises that interface.
- Static Niri outputs are now declared directly in
  `modules/niri/dotfiles/niri/outputs.kdl`. Workspace placement remains
  runtime-rendered from the selected Niri monitor profile plus the Niri
  output-name map, so the module keeps its own profile selector without
  depending on Hyprland-owned monitor profile assets. The selector lives in
  `modules/niri/profiles/profile.env` via `NIRI_MONITOR_PROFILE`.
- The supported entry path is now the UWSM wrapper installed by the `sessions`
  module. Legacy `niri-optimized-session` and the old `niri.service`
  bootstrap drop-in are intentionally removed to keep session ownership in one
  place.
- Selected long-lived GUI launch keybinds now use `uwsm app --` so terminals,
  launchers, file managers, and similar apps land in dedicated app scopes
  instead of inheriting the compositor process tree directly.
- Those `uwsm app` launches now also set explicit app names (`-a ...`) so
  scopes and journal output stay stable and easy to grep.
- Logout flows should prefer `uwsm stop` over `niri msg action quit` so the
  compositor, session targets, and UWSM-managed user services shut down
  together.
- `Ctrl+Alt+BackSpace` is reserved as an emergency exit key and runs
  `uwsm stop` directly.
- `niri-session.target` also pulls `xdg-desktop-autostart.target`; shared
  applet autostart masks live in the `wayland-autostart` module.
- Niri-specific desktop entries such as KDE Connect, Geoclue demo agent, and the
  snapper helper remain in this module because they are compositor-session
  choices rather than shared Wayland masks.
- The Niri environment layer now exposes `PATH_CORE`, `PATH_USER`, and the
  combined `PATH` explicitly so session path composition is inspectable instead
  of being implicit in the wrapper.
