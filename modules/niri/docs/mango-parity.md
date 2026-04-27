# Mango Parity Plan

Niri remains the preferred compositor for this profile because its upstream
architecture, IPC, screencast privacy, accessibility, and test culture are
stronger. Mango's advantage is the practical WM layer around it. This module
closes that gap in the repo-owned layer instead of forking Niri.

## Feature Matrix

| Mango strength | Niri module answer |
| --- | --- |
| Tag/workspace helpers | `shared/wm/workspaces.json`, generated Niri workspace rules, `niri-workspace-smart`, and `niri-osc set here`. |
| Named scratchpad | `niri-osc flow scratchpad-*`, marks, `niri-osc drop`, and documented stable `oscndrop` workspace behavior. |
| Keymode/cheatsheet metadata | `render-keybind-cheatsheet.sh` creates a generated Noctalia-readable artifact and validator checks duplicate binds. |
| Layout variety | `layouts/recipes.json` plus `layout.niriRecipe`/`layout.niriRecipes` support in `render-profile.sh`. |
| Blur/shadow/corners | `effects/background-policy.json` renders the compositor effect file and forces OSD/overview/capture surfaces crisp. |
| Runtime diagnostics | `niri-osc set doctor` reports session env, units, portals, generated includes, casts, and live IPC health. |
| Config quality gates | `scripts/validate.sh` checks generated drift, workspace semantics, package/session contracts, keybind collisions, and temporary config parsing. |

## Rules

- Do not put overview, launcher, OSD, screenshot, recording, or measurement
  overlays in a blur-true layer-rule.
- Prefer Niri IPC and generated TSV files over hard-coded app/workspace lists.
- Keep privacy rules ahead of visuals: sensitive apps and private windows should
  be blocked from screencast and screen capture by default.
- Add new workspace behavior to `shared/wm/workspaces.json` first, then render.
- Add layout behavior as a recipe when it is reusable across workspaces.
