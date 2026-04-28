# makepkg Module

This module keeps package build acceleration enabled for local Arch/CachyOS
builds.

## Managed Settings

- Enables `ccache` in `/etc/makepkg.conf` by ensuring `BUILDENV=(... ccache ...)`
  is not negated.
- Sets the user ccache maximum size to `100G` in
  `~/.config/ccache/ccache.conf`.
- Applies the same limit through `ccache --max-size=100G` when `ccache` is
  available.

The install hook is idempotent and preserves the rest of the existing
`makepkg.conf` and ccache config.

## Notes

- `ccache` helps repeated kernel and AUR builds by reusing unchanged compiler
  outputs.
- `MAKEFLAGS` and package-specific kernel options remain owned by their current
  upstream configs or PKGBUILDs.
- `modprobed-db` is already tracked in the host package manifest; use it with
  kernel PKGBUILDs that support `_localmodcfg=yes`.
