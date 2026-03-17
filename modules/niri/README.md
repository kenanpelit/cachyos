# Niri Module

This module owns the Niri compositor config, the Niri-specific
`systemd --user` startup graph, and the curated environment stack used by the
UWSM-first session wrapper.

## Entry points

- GDM and the `sessions` module now install a single Niri session entry:
  `modules/sessions/dotfiles/niri-uwsm.desktop`.
- That desktop entry launches `modules/gdm/dotfiles/niri-uwsm-session`.
- The wrapper loads the curated Niri environment stack through
  `niri-session-common` (`10-gtk.conf`, `10-niri-env.conf`, `20-qt.conf`,
  `30-ollama.conf`, and `99-dms-icons.conf` when present), normalizes path
  variables, applies the Niri session identity
  (`DESKTOP_SESSION=niri-uwsm`, `XDG_CURRENT_DESKTOP=niri`), and then hands
  off to `uwsm start -- niri-session`.
- The packaged `niri.service` is still extended via
  `dotfiles/systemd/user/niri.service.d/10-session-bootstrap.conf`, but only as
  a compatibility fallback for non-UWSM paths such as a direct `niri-session`
  launch from a TTY.
- Every unit shipped under `dotfiles/systemd/user/` is linked/enabled by the
  `user-services` module when `niri` is enabled in `hosts/*.yaml`.

## Startup flow

1. GDM starts `niri-uwsm-session`.
2. The wrapper loads the curated Niri environment stack, normalizes paths,
   applies the Niri UWSM session identity, and executes `uwsm start -- niri-session`
   (or `niri` if `niri-session` is unavailable).
3. UWSM creates the compositor service, waits for `NIRI_SOCKET`, and finalizes
   the session environment for the user manager.
4. Niri reads `~/.config/niri/config.kdl` and runs
   `spawn-at-startup "niri-session-init"`.
5. If the session is UWSM-managed, `niri-session-init` starts
   `niri-session.target` immediately and only performs runtime detection/sync as
   a fallback when UWSM did not finalize `WAYLAND_DISPLAY` or `NIRI_SOCKET`.
   If UWSM is not present, the script falls back to the older full
   `environment.d` import path.
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
  Runs `polkit-gnome-authentication-agent-1` when the selected shell backend is
  not `noctalia`.
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

## Additional shipped units

The module also ships user units that are enabled independently from the core
session target chain:

- `geoclue-agent.timer`
  Starts `geoclue-agent.service` 15 seconds after startup and keeps retrying.
- `ppp-auto-profile.timer`
  Starts `ppp-auto-profile.service` after login and then every 15 seconds.

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
  backfills missing compositor runtime variables as a safety net.
- Logout flows should prefer `uwsm stop` over `niri msg action quit` so the
  compositor, session targets, and UWSM-managed user services shut down
  together.
- `niri-session.target` also pulls `xdg-desktop-autostart.target`; shared
  applet autostart masks live in the `wayland-autostart` module.
- Niri-specific desktop entries such as KDE Connect, Geoclue demo agent, and the
  snapper helper remain in this module because they are compositor-session
  choices rather than shared Wayland masks.
