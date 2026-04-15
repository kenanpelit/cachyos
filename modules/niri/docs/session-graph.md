# Niri Session Graph

This document keeps the session-graph and UWSM-specific design notes separate
from the operational README.

## Entry Points

- The `sessions` module installs a single Niri session entry:
  `modules/sessions/dotfiles/niri-uwsm.desktop`.
- That desktop entry launches `modules/sessions/dotfiles/niri-uwsm-session`.
- TTY login reuses the same UWSM path via `osc-tty-launcher auto-tty`.
- The wrapper loads the curated Niri environment stack through
  `niri-session-common` and `~/.config/environment.d/niri-session.envlist`,
  applies the Niri session identity, normalizes path variables, clears foreign
  compositor variables, and executes `uwsm start -- niri-session`.

## Startup Flow

1. A display manager entry or TTY launcher starts `niri-uwsm-session`.
2. The wrapper loads the curated environment stack and executes
   `uwsm start -- niri-session`.
3. UWSM creates the compositor service and finalizes the session environment.
4. The repo-managed drop-in for `wayland-wm@niri\x2dsession.service` starts
   `niri-session.target` with `ExecStartPost=` once the compositor is ready.
5. `niri-session.target` pulls in `graphical-session.target`,
   `xdg-desktop-autostart.target`, `niri-session-env.service`,
   `niri-bootstrap.service`, `niri-shell-ensure.service`,
   `niri-daemons.target`, and `niri-post-daemons.target`.
6. `niri-session-env.service` publishes finalized runtime variables such as
   `NIRI_SOCKET` to `systemd --user`.
7. `niri-bootstrap.service` runs `niri-osc set init`.
8. `niri-shell-ensure.service` starts the shell backend via `osc-shell ensure`.
9. `niri-daemons.target` becomes the long-running daemon stage.
10. `niri-post-daemons.target` becomes the ordered late stage.
11. `niri-post-bootstrap.service` runs late desktop polish and the ready
    notification flow.

## Core Units

- `niri-session.target`
  Session umbrella target started by the UWSM compositor drop-in.
- `niri-session-env.service`
  Pre-bootstrap runtime env sync for `NIRI_SOCKET` and finalized vars.
- `niri-bootstrap.service`
  Early oneshot bootstrap that runs `niri-osc set init`.
- `niri-shell-ensure.service`
  Starts the shell backend via `osc-shell ensure`.
- `niri-daemons.target`
  Explicit daemon stage for long-running helpers.
- `niri-post-daemons.target`
  Ordered late stage after daemon startup.
- `niri-post-bootstrap.service`
  Late oneshot polish and readiness notification.
- `niri-status-notifier-ready.service`
  Waits for a `StatusNotifierWatcher` before tray applets start.

## Daemon Stage

These services normally belong to `niri-daemons.target` when their conditions
are met:

- `niri-polkit-agent.service`
- `niri-nm-applet.service`
- `niri-blueman-applet.service`
- `niri-snapper-tools-check.service`
- `niri-sticky.service`

Niri-only daemon-stage services are lifecycle-bound directly to
`wayland-wm@niri\x2dsession.service` via `BindsTo=`/`After=` so they stop when
the compositor dies unexpectedly.

## Shared Session Helpers

These are shared, graphical-session-scoped helpers rather than Niri-only units:

- `geoclue-agent.timer`
- `ppp-auto-profile.timer`
- `clipse.service`
- `sunsetr.service`
- `sunsetr-auto-profile.timer`

## Conditions

- Most Niri daemon-stage units require `WAYLAND_DISPLAY` and
  `XDG_CURRENT_DESKTOP=niri`.
- Units that need deterministic compositor readiness also require
  `NIRI_SOCKET`.
- Niri-only variables live under `~/.config/session-env/niri/10-niri-env.conf`
  and are consumed through the curated allowlist manifest so they do not leak
  into other compositor sessions.

## Operational Notes

- `outputs.kdl` is generated from `shared/wm/monitors.yaml`.
- `runtime/workspaces-auto.kdl` is rendered from the shared monitor manifest,
  the selected `NIRI_MONITOR_PROFILE`, and `workspaces/workspaces.json`.
- `config.kdl` is intentionally split into top-level includes under
  `dotfiles/niri/conf/`.
- Long-lived GUI launch keybinds prefer `uwsm app --` so app scopes stay
  separate from the compositor process tree.
- Logout flows should prefer `uwsm stop` over `niri msg action quit` so the
  compositor, session targets, and UWSM-managed units stop together.
