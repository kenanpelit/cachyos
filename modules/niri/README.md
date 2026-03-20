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
  `~/.config/environment.d/niri-session.envlist`, normalizes path variables,
  applies the Niri session identity
  (`DESKTOP_SESSION=niri-uwsm`, `XDG_CURRENT_DESKTOP=niri`), and then hands
  off to `uwsm start -- niri-session`.
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
4. Niri reads `~/.config/niri/config.kdl` and runs the repo-managed startup
   shim for `~/.local/bin/niri-session-init`.
5. If the session is UWSM-managed, `niri-session-init` starts
   `niri-session.target` immediately and only performs runtime detection/sync as
   a fallback when UWSM did not finalize `WAYLAND_DISPLAY` or `NIRI_SOCKET`.
   If UWSM is not present, the script falls back to the older full
   `environment.d` import path and emits a notice to the journal so the slower
   compatibility path is visible.
6. `niri-session.target` pulls in `graphical-session.target`,
   `xdg-desktop-autostart.target`, `niri-bootstrap.service`,
   `niri-daemons.target`, `niri-post-daemons.target`, and the shared
   compositor-session units enabled by other modules.
7. `niri-bootstrap.service` runs `~/.local/bin/niri-bootstrap`, which calls
   `niri-osc set init`.
8. `niri-daemons.target` becomes the daemon stage for long-running helpers.
9. `niri-post-daemons.target` becomes the ordered late stage after
   `niri-daemons.target`.
10. `niri-desktop-settings.service` syncs GNOME interface settings.
11. `niri-post-bootstrap.service` runs `~/.local/bin/niri-post-bootstrap` after
    the daemon services it depends on.

## What starts during session startup

These units make up the core Niri session chain:

- `niri-session.target`
  Session umbrella target started by `niri-session-init`.
- `niri-bootstrap.service`
  Early oneshot bootstrap. Runs `niri-osc set init`.
- `niri-daemons.target`
  Explicit daemon stage. It now declares the core Niri services it wants.
- `niri-post-daemons.target`
  Ordered late stage for session polish and optional post-daemon services.
- `niri-desktop-settings.service`
  Tracked desktop theme/icon/cursor sync.
- `niri-post-bootstrap.service`
  Late oneshot polish. Sends a best-effort "Session ready" notification after
  the daemon and desktop-settings stages complete.
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
  Runs `niri-osc sticky`.
- `niri-niriswitcher.service`
  Runs `niriswitcher`.
- Niri-only daemon-stage services are now lifecycle-bound directly to
  `wayland-wm@niri\x2dsession.service` via `BindsTo=`/`After=` so they stop
  immediately if the compositor dies unexpectedly.

The shared `clipse.service` now belongs to the standalone `clipse` module and
is bound to `graphical-session.target`, so both Niri and Hyprland reuse the
same clipboard listener unit.

The `sunsetr` module now also follows the shared `graphical-session.target`
model directly:

- `sunsetr.service`
  Mirrors upstream's native user unit while adding Niri-specific conditions, so
  it stays out of Hyprland sessions but no longer needs the old wrapper unit.
- `sunsetr-auto-profile.timer`
  Applies the scheduled preset map after startup and at each declared schedule
  boundary while the Niri session is active.

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
- `niri-sticky.service` and `niri-niriswitcher.service` also require
  `NIRI_SOCKET`.
- The repo-managed `~/.config/environment.d/*.conf` stack is the canonical
  source for Niri session variables under UWSM, but it is consumed through a
  curated Niri-specific allowlist manifest so ad-hoc user overrides do not
  leak into the Niri session wrapper. `niri-session-init` avoids re-importing
  that full
  static environment when UWSM is already managing the session and only
  backfills missing compositor runtime variables as a safety net. When that
  fallback path is used, it emits a warning to the journal so session drift is
  visible.
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
