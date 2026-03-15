# Niri Module

This module owns the Niri compositor config, its user-level systemd units, and
the small amount of session glue needed to hand off a GDM login to
`systemd --user`.

## Entry points

- GDM launches `modules/gdm/dotfiles/niri-optimized-session`.
- The wrapper forces `DESKTOP_SESSION`, `XDG_SESSION_DESKTOP`, and
  `XDG_CURRENT_DESKTOP` to `niri` before the compositor starts.
- The wrapper pre-warms `systemd --user` with `systemctl --user set-environment`
  and then executes `niri-session` (fallback: `niri --session`).
- The repo does not replace the packaged Niri service; instead it extends it via
  `dotfiles/systemd/user/niri.service.d/10-session-bootstrap.conf`.
- Every unit shipped under `dotfiles/systemd/user/` is linked/enabled by the
  `user-services` module when `niri` is enabled in `hosts/*.yaml`.

## Startup flow

1. GDM starts `niri-optimized-session`.
2. The wrapper aligns the session identity to `niri` and preloads those values
   into `systemd --user`.
3. The wrapper executes `niri-session` or `niri --session`.
4. Once the compositor process is up, the packaged Niri unit runs the repo
   drop-in `10-session-bootstrap.conf`.
5. That `ExecStartPost` calls `niri-osc set env`.
6. `niri-osc set env` exports the live session environment into
   `systemd --user` and starts `niri-session.target`.
7. `niri-session.target` pulls in `graphical-session.target`,
   `xdg-desktop-autostart.target`, `niri-bootstrap.service`, and
   `niri-daemons.target`.
8. `niri-bootstrap.service` runs `~/.local/bin/niri-bootstrap`, which calls
   `niri-osc set init`.
9. `niri-daemons.target` becomes the daemon stage for long-running helpers.
10. `niri-post-bootstrap.service` runs `~/.local/bin/niri-post-bootstrap` for
    late polish.

## What starts during session startup

These units make up the core Niri session chain:

- `niri-session.target`
  Session umbrella target started by `niri-osc set env`.
- `niri-bootstrap.service`
  Early oneshot bootstrap. Runs `niri-osc set init`.
- `niri-daemons.target`
  Logical daemon stage for long-running helpers.
- `niri-post-bootstrap.service`
  Late oneshot polish. Applies GNOME interface settings and sends a best-effort
  "Session ready" notification.

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
  Starts `ppp-auto-profile.service` after login and then every 20 seconds.
- `niri-login-prompts.service`
  Warmup helper for `osc-login-prompts`. It is shipped with the module, but it
  is not pulled in by `niri-daemons.target`; start semantics are host-specific.

## Conditions and notes

- The daemon-stage Niri services generally require `WAYLAND_DISPLAY` and
  `XDG_CURRENT_DESKTOP=niri`.
- `niri-sticky.service` and `niri-niriswitcher.service` also require
  `NIRI_SOCKET`.
- `niri-session.target` also pulls `xdg-desktop-autostart.target`; shared applet
  autostart masks live in the `wayland-autostart` module.
- Niri-specific desktop entries such as KDE Connect, Geoclue demo agent, and the
  snapper helper remain in this module because they are compositor-session
  choices rather than shared Wayland masks.
