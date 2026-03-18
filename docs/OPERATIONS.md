# Operations Runbook

This runbook documents expected runtime state, failure fallback, and quick diagnostics for high-impact modules.

## Mullvad + Blocky DNS State Machine

Target invariant:

- Mullvad connected and healthy => `blocky` stopped, resolver should be Mullvad (`10.64.0.1`).
- Mullvad disconnected, revoked, timeout, or unhealthy => `blocky` started, resolver should be local (`127.0.0.1`, optionally `::1`).

Core commands:

- Toggle with fallback: `osc-mullvad toggle --with-blocky`
- Enforce fail-safe state: `osc-mullvad ensure`
- Check DNS/runtime: `osc-dns status --verbose`

Failure fallback (manual):

```bash
sudo mullvad auto-connect set off
sudo mullvad lockdown-mode set off
sudo mullvad disconnect
sudo systemctl restart blocky
osc-dns status --verbose
```

Expected after fallback:

- `blocky: active`
- `mullvad: Disconnected` or `Warning: This device has been revoked.`
- `resolv.conf: 127.0.0.1, ::1` (or at least `127.0.0.1`)

## Niri + Hyprland Runtime Flow

Session launchers are user-home agnostic and call scripts via `$HOME/.local/bin`:

- `modules/sessions/dotfiles/niri-optimized.desktop`
- `modules/sessions/dotfiles/gnome-optimized.desktop`

Operational checks:

```bash
which niri-osc
which hypr-osc
which gnome_tty
niri validate -c "$HOME/.config/niri/config.kdl"
```

If keybind-spawned scripts work in terminal but not via compositor keybinds, verify the keybind uses `spawn "sh" "-lc" ...` (or equivalent wrapper that sets shell environment).

## Modules Using `post_hook_behavior: ask`

Current `ask` modules:

- `modules/hyprpanel`
- `modules/flatpak`
- `modules/xdg-mimes`
- `modules/fusuma`
- `modules/connect`
- `modules/mpd`
- `modules/transmission`
- `modules/gnome`
- `modules/search`
- `modules/bt`

Operator policy during `dcli sync`:

- Run hook now when the module changes system state needed immediately (services, mime/default handlers, runtime dirs).
- Skip temporarily only when you intentionally defer side effects.
- If skipped, run the module hook manually before debugging related runtime behavior.

Refresh this list any time module metadata changes:

```bash
rg -n "post_hook_behavior:\\s*ask" modules/*/module.yaml
```
