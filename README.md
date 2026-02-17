# CachyOS Declarative Configuration

<div align="center">
  <img src="https://img.shields.io/badge/CachyOS-Arch_Linux-blue?style=for-the-badge&logo=archlinux&logoColor=white" alt="CachyOS">
  <img src="https://img.shields.io/badge/Manager-dcli-green?style=for-the-badge&logo=yaml&logoColor=white" alt="dcli">
  <img src="https://img.shields.io/badge/Compositors-Niri%20%2B%20Hyprland-6c5ce7?style=for-the-badge" alt="Niri + Hyprland">
</div>

Declarative, modular desktop/system configuration for CachyOS (Arch Linux), managed with [dcli](https://gitlab.com/theblackdon/dcli).

The repository is tuned for a real daily-driver workstation and emphasizes:

- reproducibility (minimal config drift)
- modularity (small, focused modules)
- operational reliability (service orchestration + documented runbooks)

## Scope

This repo manages:

- base system packages (official + AUR)
- shells and CLI tools (`zsh`, `nvim`, `tmux`, `yazi`, etc.)
- Wayland desktop stack (`niri`, `hyprland`, portals, session entries)
- user services (systemd `--user` units and timers)
- networking/security modules (`ufw`, `fail2ban`, `blocky`, Mullvad helpers)
- media/workflow tooling (`mpv`, `mpd`, `copyq`, `dms`, `walker`, etc.)
- MIME/default app mappings

## Configuration Model

The repo uses a host-pointer + host-profile model:

- `config.yaml`: points to active host (currently `hay`)
- `hosts/<host>.yaml`: ordered module list + host-specific settings
- `modules/<name>/`: each module defines packages, dotfiles, and hooks

Most modules follow this pattern:

- `module.yaml` -> metadata, dotfile mappings, hook policy
- `packages.yaml` -> package list
- `dotfiles/` -> managed files
- `scripts/` -> install/post-install logic

## Quick Start

### 1. Clone

```bash
git clone --recurse-submodules https://github.com/kenanpelit/cachyos.git ~/.cachy
```

### 2. Register repo as dcli config root

```bash
mkdir -p ~/.config
ln -sfn ~/.cachy ~/.config/arch-config
```

### 3. Sync

```bash
cd ~/.cachy
sudo -E dcli sync
```

After first sync, log out/in (or reboot) to ensure session-level services and desktop entries are fully applied.

## Daily Workflow

```bash
cd ~/.cachy
# edit modules or host profile
sudo -E dcli sync
```

Recommended maintenance:

```bash
git pull --rebase
git submodule update --init --recursive
sudo -E dcli sync
```

## Repository Layout

```text
.
├── config.yaml            # active host pointer
├── hosts/                 # host profiles (module order + host settings)
├── modules/               # modular configuration units
│   ├── niri/              # primary compositor profile
│   ├── hyprland/          # secondary compositor profile
│   ├── dms/               # shell/launcher stack
│   ├── user-services/     # user service enable/normalize flow
│   ├── grub/              # bootloader customization
│   ├── firewall/          # ufw policy
│   ├── fail2ban/          # intrusion mitigation
│   ├── blocky/            # DNS filtering/failsafe integration
│   └── ...
└── docs/
    └── OPERATIONS.md      # runtime checks and incident playbooks
```

## Operational Notes

- Runbook: `docs/OPERATIONS.md`
- Host profile: `hosts/hay.yaml`
- Active host pointer: `config.yaml`
- Some modules intentionally use `post_hook_behavior: ask`; review prompt output during `dcli sync`.

## Portability and Safety

This configuration is opinionated and hardware/workflow specific.

Before applying on another machine, review at minimum:

- `hosts/<target>.yaml`
- `modules/kernel/`
- `modules/grub/`
- `modules/firewall/`
- `modules/blocky/`
- `modules/sessions/`

## License

MIT (`LICENSE`).

## Credits

- [dcli](https://gitlab.com/theblackdon/dcli)
- [CachyOS](https://cachyos.org/)
