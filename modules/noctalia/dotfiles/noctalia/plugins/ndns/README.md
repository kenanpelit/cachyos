# DNS / VPN Switcher

![ndns preview](preview.png)

A Noctalia plugin fork that combines two layers of network control:

- managed protection modes via `osc-mullvad`
- direct DNS presets via NetworkManager (`nmcli`)

## Available modes

- **Mullvad**: connect Mullvad, keep Blocky off
- **Blocky**: disconnect Mullvad if needed, enable Blocky fallback
- **Default (ISP)**: stop managed protection and restore NetworkManager auto DNS
- **Toggle**: flip between Mullvad and Blocky using `osc-mullvad toggle --with-blocky`
- **Sync / Repair**: run `osc-mullvad ensure --grace 0`

## DNS presets

The plugin can also apply these direct DNS presets:

- Google: `8.8.8.8 8.8.4.4`
- Cloudflare: `1.1.1.1 1.0.0.1`
- OpenDNS: `208.67.222.222 208.67.220.220`
- AdGuard: `94.140.14.14 94.140.15.15`
- Quad9: `9.9.9.9 149.112.112.112`

When a direct DNS preset is selected, the plugin first tries to disable Mullvad and stop Blocky, then writes the DNS values to the active NetworkManager connection.

## Requirements

- `mullvad` CLI
- `blocky.service` (optional, if you use Blocky mode)
- `nmcli` / NetworkManager
- `osc-mullvad`
- `sudo -n` or `pkexec` for stopping Blocky when switching to direct DNS presets

## Notes

- Status detection prioritizes Mullvad / Blocky state over raw DNS presets.
- If Blocky is active and cannot be stopped, direct DNS preset actions will fail instead of silently lying about the state.
