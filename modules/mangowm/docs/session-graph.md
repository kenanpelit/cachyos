# MangoWM Session Graph

This document keeps the Mango session-graph and UWSM-specific design notes
separate from the operational README.

## Entry Points

- The `sessions` module installs a single Mango session entry:
  `modules/sessions/dotfiles/mango-uwsm.desktop`.
- That desktop entry launches `modules/sessions/dotfiles/mango-uwsm-session`.
- The wrapper loads the curated Mango environment stack through
  `mango-session-common` and `~/.config/environment.d/mangowm-session.envlist`,
  applies the Mango session identity, normalizes path variables, clears
  foreign compositor variables, and executes `uwsm start -- mango-session`.

## Startup Flow

1. A display manager entry or TTY launcher starts `mango-uwsm-session`.
2. The wrapper loads the curated environment stack and executes
   `uwsm start -- mango-session`.
3. UWSM creates the compositor service and finalizes the session environment.
4. The repo-managed drop-in for `wayland-wm@mango\x2dsession.service` starts
   `mangowm-session.target` with `ExecStartPost=` once the compositor is ready.
5. `mangowm-session.target` pulls in `graphical-session.target`,
   `xdg-desktop-autostart.target`, `mango-session-env.service`,
   `mango-bootstrap.service`, `mango-audio-init.service`,
   `mango-arrange.service`, `mango-shell-ensure.service`,
   `mango-lid-switch-inhibit.service`, `mango-lid-switch-watch.service`,
   `mango-daemons.target`, `mango-post-daemons.target`, and
   `mango-session-ready.target`.
6. `mango-session-env.service` publishes finalized runtime variables to
   `systemd --user`.
7. `mango-bootstrap.service` runs the early Mango bootstrap stage.
8. `mango-arrange.service` reconciles the current monitor/tag view against
   `~/.config/mango/generated/profile.conf` through the runtime compatibility
   mirror.
9. `mango-shell-ensure.service` starts the shell backend.
10. `mango-daemons.target` becomes the long-running daemon stage.
11. `mango-post-daemons.target` becomes the ordered late stage.
12. `mango-post-bootstrap.service` performs late desktop polish.
13. `mango-session-ready.target` marks the session as ready once arrange,
    settings sync, and post-bootstrap polish have all completed.

## Core Units

- `mangowm-session.target`
  Session umbrella target started by the UWSM compositor drop-in.
- `mango-session-env.service`
  Pre-bootstrap runtime env sync.
- `mango-bootstrap.service`
  Early oneshot bootstrap.
- `mango-arrange.service`
  Profile-aware monitor/tag reconcile stage.
- `mango-shell-ensure.service`
  Starts the shell backend.
- `mango-lid-switch-inhibit.service`
  Takes the user-session lid-switch inhibitor so logind does not suspend first.
- `mango-lid-switch-watch.service`
  Watches lid state changes and routes lid-close through Noctalia lock-and-suspend.
- `mango-daemons.target`
  Explicit daemon stage for long-running helpers.
- `mango-post-daemons.target`
  Ordered late stage after daemon startup.
- `mango-post-bootstrap.service`
  Late oneshot polish.
- `mango-session-ready.target`
  Ready-stage target that binds together the last required oneshots.
- `mango-status-notifier-ready.service`
  Readiness gate for tray-dependent applets.

## Daemon Stage

These services normally belong to `mango-daemons.target` when their conditions
are met:

- `mango-polkit-agent.service`
- `mango-nm-applet.service`
- `mango-blueman-applet.service`

The daemon target and each long-lived applet now also bind to
`wayland-wm@mango\x2dsession.service` so a compositor stop/crash tears down the
session-side applets instead of leaving them orphaned.

## Conditions

- Most Mango session units require `WAYLAND_DISPLAY` and
  `XDG_SESSION_DESKTOP=mango`.
- Canonical generated assets live under `~/.config/mango/generated/` and are
  rendered by the Mango module generators.
- Runtime assets live under `~/.config/mango/runtime/` as compatibility
  symlinks and are refreshed by `modules/mangowm/scripts/ensure-runtime-files.sh`.
- Shared monitor/output placement lives in `shared/wm/monitors.yaml`.
- Shared workspace semantics live in `shared/wm/workspaces.json`.

## Operational Notes

- `packages.yaml`, `generated/theme.conf`, `generated/profile.conf`,
  `generated/workspace-rules.conf`, `generated/workspace-binds.conf`, and
  `generated/keybind-cheatsheet.conf` are repo-owned generated outputs.
- `runtime/profile.conf`, `runtime/workspace-rules.conf`,
  `runtime/workspace-binds.conf`, and `runtime/keybind-cheatsheet.conf` are
  compatibility symlinks for helper/scripts that still read the runtime tree.
- Logout flows should prefer `uwsm stop` over compositor-local quit paths so
  the compositor, session targets, and UWSM-managed units stop together.
