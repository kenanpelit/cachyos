# Chrome Profile Launchers — Design

**Date:** 2026-08-12
**Status:** Approved

## Goal

Mirror the existing Brave/Helium per-profile launchers for **google-chrome**, so
the user gets `start-chrome-<name>` scripts (e.g. `start-chrome-kenp`) matching
every `start-brave-<name>`.

## Decision (user-approved)

- **Profile data model:** every profile is a **fresh, isolated** Chrome instance.
  No seeding from the existing `google-chrome` "Kenan" profile. Sign in once per
  profile; data then persists in that profile's own user-data-dir.
- **Isolated root:** `~/.chrome` — each profile lives at `~/.chrome/<class>`
  (Brave uses `~/.brave/isolated/<class>`; Chrome uses `~/.chrome/<class>` per
  the user's request that everything live under `~/.chrome`).

## Profiles (14)

Mirror of `BRAVE_BROWSERS` + one incognito, with `COMMAND=profile_chrome`:

`kenp, nil, ai, compecta, block, whats, exclude, youtube, tiktok, spotify,
discord, proxy, whatsapp` + `kenp-incognito`.

Args copied verbatim from `BRAVE_BROWSERS` (same workspace/vpn/wait/fullscreen
and the same flag patterns: named profile vs `--youtube/--tiktok/--spotify/
--discord/--whatsapp` web-app shortcuts, `--app=`, `--app-id=`, `--proxy`,
`--incognito`, `--class`/`--title`, `--separate`, `--restore-last-session`).

## Components

### 1. `modules/chrome/scripts/profile_chrome.sh` (new)

A **lean fork** of `profile_brave.sh`. Because all profiles are fresh-isolated,
the Brave Local-State/`jq` resolution + seeding machinery
(`resolve_profile_source`, `ensure_isolated_profile_dir`, profile create/delete)
is **dropped**. Kept for parity:

- Chrome binary auto-detect: `google-chrome-stable` → `google-chrome` → `chrome`.
- Always fresh isolated: `--user-data-dir=~/.chrome/<class>` +
  `--profile-directory=Default` (Chrome seeds a fresh Default itself).
- Web-app shortcuts (`--youtube/--tiktok/--spotify/--discord/--whatsapp` →
  `--app=<url>`), proxy (`--proxy`, proxy profile), `--incognito`,
  `--class`/`--title`, `--separate`, pass-through of unknown flags
  (`--app-id=`, `--restore-last-session`).
- Wayland flags: `--ozone-platform=wayland`,
  `--enable-features=UseOzonePlatform,WaylandWindowDecorations,VaapiVideoDecoder,TouchpadOverscrollHistoryNavigation`,
  `--disable-features=Vulkan`.
- Symlinked to `~/.local/bin/profile_chrome`.

### 2. `modules/scripts/bin/semsumo.sh` (edit)

- New `declare -A CHROME_BROWSERS` (13 entries) after `BRAVE_BROWSERS`.
- Add `chrome-kenp-incognito` to `INCOGNITO_BROWSERS`.
- Wire `CHROME_BROWSERS` into: `get_browser_profiles` (chrome→array),
  `generate_all_scripts` loop, `resolve_profile_config`, `launch_profile`.

### 3. `modules/chrome/module.yaml` + `scripts/install.sh` + `dotfiles/chrome-launcher/config.conf` (new)

Mirror the Brave module: ships a default launcher config, symlinks
`profile_chrome` (and the generated `start-chrome-*`) into `~/.local/bin`.

## Build steps

1. Write `profile_chrome.sh`, module files.
2. Edit `semsumo.sh`.
3. `semsumo generate --all` → `modules/scripts/start/start-chrome-*.sh` (14).
4. Symlink `profile_chrome` + `start-chrome-*` into `~/.local/bin`.

## Verification

- `bash -n` on profile_chrome.sh, semsumo.sh, and each generated script.
- Confirm 14 `start-chrome-*` generated and symlinked.
- Launch one (e.g. `start-chrome-nil`) to confirm a fresh `~/.chrome/nil`
  Chrome window appears.

## Out of scope

- No migration of existing Chrome "Kenan" data into any profile.
- No `chromectl` management dispatcher (Brave has `bravectl`); can be added later
  if wanted.
