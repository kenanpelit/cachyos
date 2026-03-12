#!/usr/bin/env bash
set -euo pipefail

module_root="$(cd "$(dirname "$0")/.." && pwd)"
bin_dir="$HOME/.local/bin"
systemd_dir="$HOME/.config/systemd/user"
host_name="com.github.browserpass.native.json"
host_path="$bin_dir/browserpass-native-host"
helium_root="$HOME/.config/net.imput.helium"
helium_isolated_root="$HOME/.helium/isolated"

mkdir -p "$bin_dir" "$systemd_dir"
chmod +x "$module_root/scripts/browserpass-native-host" || true
ln -sf "$module_root/scripts/browserpass-native-host" "$host_path"
ln -sf "$module_root/dotfiles/systemd/user/browserpass.socket" "$systemd_dir/browserpass.socket"
ln -sf "$module_root/dotfiles/systemd/user/browserpass@.service" "$systemd_dir/browserpass@.service"

write_manifest() {
  local dir="$1"
  mkdir -p "$dir"
  cat >"$dir/$host_name" <<EOF
{
  "name": "com.github.browserpass.native",
  "description": "Browserpass native component via systemd user socket",
  "path": "$host_path",
  "type": "stdio",
  "allowed_origins": [
    "chrome-extension://naepdomgkenhinolocfifgehidddafch/",
    "chrome-extension://pjmbgaakjkbhpopmakjoedenlfdmcdgm/",
    "chrome-extension://klfoddkbhleoaabpmiigbmpbjfljimgb/"
  ]
}
EOF
}

cleanup_manifest_dirs=(
  "$HOME/.config/BraveSoftware/Brave-Browser/NativeMessagingHosts"
  "$HOME/.config/BraveSoftware/Brave-Browser-Beta/NativeMessagingHosts"
  "$HOME/.config/chromium/NativeMessagingHosts"
  "$HOME/.config/google-chrome/NativeMessagingHosts"
  "$HOME/.config/google-chrome-beta/NativeMessagingHosts"
)

for dir in "${cleanup_manifest_dirs[@]}"; do
  rm -f "$dir/$host_name"
done

manifest_dirs=(
  "$helium_root/NativeMessagingHosts"
)

for dir in "${manifest_dirs[@]}"; do
  write_manifest "$dir"
done

if [[ -d "$helium_isolated_root" ]]; then
  while IFS= read -r -d '' helium_dir; do
    write_manifest "$helium_dir/NativeMessagingHosts"
  done < <(find "$helium_isolated_root" -mindepth 1 -maxdepth 1 -type d -print0 2>/dev/null)
fi

if command -v systemctl >/dev/null 2>&1; then
  systemctl --user daemon-reload >/dev/null 2>&1 || true
  systemctl --user enable --now browserpass.socket >/dev/null 2>&1 || true
fi
