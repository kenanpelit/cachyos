# Network Manager VPN

![Preview](preview.png)

Plugin to connect to your VPN connections from the bar and Control Center. Supports OpenVPN and WireGuard connections managed by NetworkManager.

## Usage

Install the plugin and add to your bar:

- **Bar widget** — A lock icon that show if there is a connection active. Click it to open the VPN panel.
- **VPN panel** — lists all configured VPN connections

The panel refreshes automatically every 5 seconds. You can also trigger a manual refresh with the refresh button.

## Requirements

- **Noctalia Shell** ≥ 3.6.0
- **NetworkManager** with `nmcli`
- VPN connections must be configured in NetworkManager