# MangoWM Module

Modular MangoWM setup with UWSM-first startup, shared monitor profiles, and
workspace routing generated from the canonical Niri workspace manifest.

## What It Manages

- `~/.config/mango/config.conf`
- `~/.config/mango/conf.d/*`
- `~/.config/mango/generated/*`
- `~/.config/session-env/mangowm/10-mangowm.conf`
- `~/.config/environment.d/mangowm-session.envlist`
- `~/.config/xdg-desktop-portal/mango-portals.conf`
- `~/.config/systemd/user/mangowm-*.{target,service}`

## Generated Assets

- `generated/theme.conf`
  - Rendered from `theme/theme.env`
  - Current default assumes `mangowm`, so scenefx keys like blur,
    shadows, and border radius are rendered as configured
- `generated/profile.conf`
  - Rendered from `shared/wm/monitors.yaml` and `profiles/profile.env`
- `generated/workspace-rules.conf`
  - Rendered from `modules/niri/workspaces/workspaces.json`

## Validation

Run:

```bash
modules/mangowm/scripts/validate.sh
```

This checks generator drift, shell syntax, and the Mango config parser with:

```bash
mango -c modules/mangowm/dotfiles/mango/config.conf -p
```
