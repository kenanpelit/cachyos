# topgrade Module

This module installs Topgrade and manages the host config at
`~/.config/topgrade.toml`.

## Managed Settings

- Installs the `topgrade` package from the configured Arch/CachyOS package
  sources.
- Uses `paru` for the Arch system update step.
- Disables firmware and snap updates by default.
- Pulls `~/.cachy` and git repositories under `~/.kod/*/` before other update
  steps.
- Runs Flatpak last and uses the user-scope Flatpak installation used by
  `hosts/hay.yaml`.
- Enables cleanup and sends desktop notifications only when a run fails.
- Enables `pip-review`, but ignores pip step failures so one Python environment
  does not block the rest of the maintenance run.

## Usage

Preview what Topgrade would do:

```sh
topgrade --dry-run --show-skipped
```

Run the update:

```sh
topgrade
```

Print the installed version's full configuration reference:

```sh
topgrade --config-reference
```

Firmware is intentionally disabled here. Check firmware separately with `fwupdmgr`
when you actually want to review firmware changes.
