# Handy

Handy is a local, offline speech-to-text desktop app built with Tauri.

What it does:
- stays running in the background
- records when triggered
- transcribes locally with Whisper / Parakeet
- pastes text back into the focused app

Relevant upstream notes from `~/.kod/handy`:
- Linux/Wayland text injection works best with `wtype`
- on Wayland, global hotkeys should be owned by the compositor/window manager
- the binary supports:
  - `handy --toggle-transcription`
  - `handy --toggle-post-process`
  - `handy --cancel`
  - `handy --start-hidden`

This module provides:
- package management for `handy` and `wtype`
- a user service that starts Handy hidden with the tray icon
- a helper command: `handyctl`

Useful commands:
```bash
handyctl status
handyctl open
handyctl toggle
handyctl post
handyctl cancel
handyctl logs
```

Niri / Wayland recommendation:
- bind a compositor shortcut to `handyctl toggle`
- optional second shortcut: `handyctl post`

Typical Linux user data location:
- Tauri app data dir, usually under `~/.local/share/com.pais.handy/`
- history database: `history.db`
- recordings directory: `recordings/`
- settings store: `settings_store.json`
