<h1 align="center">CachyOS Declarative Infrastructure</h1>

<div align="center">
  <img src="https://img.shields.io/badge/CachyOS-Arch_Linux-blue?style=for-the-badge&logo=archlinux&logoColor=white" alt="CachyOS">
  <img src="https://img.shields.io/badge/Framework-DCLI%20v2-green?style=for-the-badge&logo=yaml&logoColor=white" alt="dcli">
  <img src="https://img.shields.io/badge/Host-hay-orange?style=for-the-badge" alt="hay">
  <img src="https://img.shields.io/badge/Desktop-Hyprland%20%2B%20Niri%20%2B%20GNOME-1f6feb?style=for-the-badge" alt="Hyprland + Niri + GNOME">
</div>

<p align="center">
  <strong>A high-performance, modular, and declarative configuration framework for CachyOS workstations. Powered by <a href="https://gitlab.com/theblackdon/dcli">dcli</a> and engineered for operational excellence.</strong>
</p>

---

## 🚀 Overview

This repository represents the **"Source of Truth"** for a production-grade CachyOS environment. Unlike traditional dotfiles, this is a modular configuration framework designed to eliminate configuration drift, automate day-2 operations, and provide a standardized environment across display-manager sessions, TTY launch paths, and multiple desktop stacks (Niri, Hyprland, GNOME).

### Core Pillars
- 🧩 **Strict Modularity**: 85+ implementation units with explicit dependency tracking.
- 🏗️ **Architectural Integrity**: Shared shell libraries for atomic updates and safe installations.
- 🩺 **Health Monitoring**: Integrated validation hooks to ensure configuration validity.
- 📖 **Self-Documenting**: Automatic markdown generation from script headers.
- ⚡ **Performance Optimized**: Minimized login overhead and parallelized service startup.

---

## 🏗️ System Architecture

The framework is built on a layered implementation model:

- **Host Profiles (`hosts/*.yaml`)**: Ordered module stacks defining the personality of a machine.
- **Shared Library (`modules/base/lib/`)**: Centralized logic for user detection, error handling, and file operations (`core.sh`).
- **Standardized Environment**: Conflict-free session variables managed via `environment.d`.
- **Atomic Hooks**: Pre/Post-install scripts ensuring consistent state transitions.

### Modern Module Contract
Each module in `modules/` follows a standardized declarative schema:
```yaml
tags: [desktop, wm]          # Operational grouping
description: "Brief intent"  # Human-readable metadata
depends_on: [base, scripts]  # Explicit dependency graph
dotfiles: [...]              # Managed configuration files
packages: [...]              # Multi-source package lists (AUR, Repo, Flatpak)
```

---

## 🛠️ Automated Toolset

The system includes a suite of custom-engineered operational tools:

- **`niri-osc` / `hypr-osc`**: Advanced compositor control suites.
- **`osc-shell`**: Unified router for desktop IPC actions and state management.
- **`mdots-docgen`**: Automatic documentation engine for local scripts.
- **`vv`**: Optimized daily journaling and scratchpad manager.

> [!TIP]
> View the full catalog of 100+ custom scripts in **[docs/SCRIPTS.md](./docs/SCRIPTS.md)**.

---

## 📥 Quick Start

### 1. Bootstrap
```bash
git clone --recurse-submodules https://github.com/kenanpelit/cachyos.git ~/.cachy
mkdir -p ~/.config
ln -sfn ~/.cachy ~/.config/mdots
```

### 2. Synchronize State
```bash
cd ~/.cachy
sudo -E mdots sync
```

## ⌨️ Keyboard Layout Warning

This repo is opinionated about keyboard defaults and assumes **Turkish F** unless you deliberately change it:

- **TTY / login manager**: Turkish F (`KEYMAP=trf`)
- **Niri**: `layout "tr"` + `variant "f"`
- **Hyprland**: `kb_layout=tr` + `kb_variant=f`

If you do **not** use Turkish F, change the layout before your first serious `mdots sync`. Otherwise you can end up with mixed keyboard behavior between TTY, Lemurs/LiDM, Niri, and Hyprland.

Current source locations:

- `TTY / Lemurs / LiDM`: live `/etc/vconsole.conf`
- `Niri`: `modules/niri/dotfiles/niri/config.kdl`
- `Hyprland`: `modules/hyprland/dotfiles/hypr/conf.d/30-input.conf`

Recommended helper:

```bash
osc-keyboard-layout status
```

Example output on this host:

```text
Repo-managed layout
  Niri:      layout=tr variant=f options=ctrl:nocaps
  Hyprland:  layout=tr variant=f options=ctrl:nocaps

Live TTY/login-manager layout
  vconsole:  layout=tr variant=f keymap=trf
```

Common usage:

```bash
osc-keyboard-layout set trf
osc-keyboard-layout set trq
osc-keyboard-layout set --layout us --variant '' --tty-keymap us
```

What it updates:

- Repo-managed Niri keyboard block
- Repo-managed Hyprland input block
- Live `/etc/vconsole.conf` for TTY and text-mode login managers

After changing layout:

```bash
sudo -E mdots sync
```

Notes:

- This is important because TTY and the display manager read `vconsole`, while Niri and Hyprland read their own compositor configs.
- If you only change one side, login and desktop sessions can disagree about the active keyboard layout.
- TTY/login-manager changes apply immediately best-effort and definitely on next login.
- Niri and Hyprland layout changes apply on the next session start, or after you reload/re-enter the compositor.
- If you want to update only repo files or only the live TTY side, use `--repo-only` or `--live-only`.

---

## 📑 Repository Structure

| Directory | Purpose |
| :--- | :--- |
| `hosts/` | Active host definitions (e.g., `hay.yaml`) |
| `modules/base/` | Core library and bootstrap logic |
| `modules/scripts/` | Unified binary management and system helpers |
| `modules/hyprland/` | UWSM-managed Hyprland compositor, session graph, and routing |
| `modules/niri/` | Optimized scrollable-tiling compositor setup |
| `modules/noctalia/` | High-performance Quickshell-based desktop UI |
| `docs/` | Operational runbooks and auto-generated manuals |

---

## 🛤️ Session Entry Points

Primary login path:
- **GDM session chooser**: `Hyprland (UWSM)`, `Niri (UWSM)`, `GNOME (Optimized)`

Secondary TTY routing via `osc-tty-launcher auto-tty`:
- **TTY2**: Hyprland (UWSM)
- **TTY3**: Niri (UWSM)
- **TTY4**: GNOME
- **TTY5**: Ubuntu VM via Sway profile
- **TTY6**: Manual launcher / recovery

Notes:
- The display-manager path is the canonical entrypoint for daily use.
- Hyprland and Niri sessions both enter through UWSM-managed wrappers installed by the `sessions` module.
- TTY routing exists as an operational fallback and recovery path, not as the primary session orchestration layer.

## 🧭 UWSM Session Model

Hyprland and Niri are both started through repo-managed UWSM wrappers rather
than being launched as loose compositor processes. In practice this means each
Wayland session is brought up under `systemd --user`, with explicit compositor
units, finalized runtime environment variables, and a deterministic startup and
shutdown path.

This also improves lifecycle management after login. Compositor-bound daemons
can be tied directly to the compositor service, while long-lived GUI
applications can be launched through `uwsm app` into named systemd scopes
instead of inheriting the compositor process tree directly.

---

## 🔧 Operational Maintenance

**Update and Rebase System:**
```bash
git pull --rebase && git submodule update --init --recursive && sudo -E mdots sync
```

**Validate Configurations:**
```bash
niri validate -c ~/.config/niri/config.kdl
```

## 🔒 Commit Safety

Enable local repo hooks once:
```bash
git config --local core.hooksPath .githooks
```

- `.githooks/pre-commit` scans staged files and changed submodules for common secret/token patterns.
- If a line is intentionally safe, append `secret-scan: allow` on that same line.
- `sathiAi` is a submodule; keep API keys in runtime settings (ignored/local), never in tracked source.

---

## 📜 License & Credits

- **License**: MIT (`LICENSE`)
- **Engine**: [dcli](https://gitlab.com/theblackdon/dcli)
- **Distribution**: [CachyOS](https://cachyos.org/)

<div align="right">
  <em>Last modernized: March 2026</em>
</div>
