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
  `niri-session-common` (`10-gtk.conf`, `10-niri-env.conf`, `20-qt.conf`,
  `30-ollama.conf`, and `99-dms-icons.conf` when present), normalizes path
  variables, applies the Niri session identity
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
   `niri-daemons.target`, and `niri-post-bootstrap.service`.
7. `niri-bootstrap.service` runs `~/.local/bin/niri-bootstrap`, which calls
   `niri-osc set init`.
8. `niri-daemons.target` becomes the daemon stage for long-running helpers.
9. `niri-post-bootstrap.service` runs `~/.local/bin/niri-post-bootstrap` after
   the daemon services it depends on.

## What starts during session startup

These units make up the core Niri session chain:

- `niri-session.target`
  Session umbrella target started by `niri-session-init`.
- `niri-bootstrap.service`
  Early oneshot bootstrap. Runs `niri-osc set init`.
- `niri-daemons.target`
  Explicit daemon stage. It now declares the core Niri services it wants.
- `niri-post-bootstrap.service`
  Late oneshot polish. Applies GNOME interface settings and sends a best-effort
  "Session ready" notification. It is ordered after the daemon services rather
  than after the target itself to avoid systemd ordering cycles.

These services belong to `niri-daemons.target` and normally come up with the
session once the environment conditions are satisfied:

- `niri-polkit-agent.service`
  Runs `polkit-gnome-authentication-agent-1`. The Niri session now owns the
  polkit agent directly, independent of the selected shell backend.
- `niri-nm-applet.service`
  Runs `nm-applet --indicator`.
- `niri-blueman-applet.service`
  Runs `blueman-applet`.
- `niri-snapper-tools-check.service`
  Runs the snapshot boot check for `snapper-tools`.
- `niri-sticky.service`
  Runs `niri-osc sticky`.
- `niri-niriswitcher.service`
  Runs `niriswitcher`.
- Niri-only daemon-stage services are now lifecycle-bound directly to
  `wayland-wm@niri\x2dsession.service` via `BindsTo=`/`After=` so they stop
  immediately if the compositor dies unexpectedly.

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
  curated Niri-specific allowlist so ad-hoc user overrides do not leak into the
  Niri session wrapper. `niri-session-init` avoids re-importing that full
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
- The UWSM session fallback path intentionally keeps a minimal default `PATH`;
  personal helper directories such as `.iptv/bin`, zinit shims, and GOPATH
  bins are no longer injected into the desktop session bootstrap.
