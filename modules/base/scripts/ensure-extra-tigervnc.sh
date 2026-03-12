#!/usr/bin/env bash
set -euo pipefail

pkg_name="tigervnc"
pkg_spec="extra/tigervnc"
desired_repo="extra"

current_repo="$(
  pacman -Qi "$pkg_name" 2>/dev/null | awk -F' *: *' '/^Installed From/ {print $2; exit}'
)"

if [[ "$current_repo" == "$desired_repo" ]]; then
  exit 0
fi

tmp_config="$(mktemp)"
cleanup() {
  rm -f "$tmp_config"
}
trap cleanup EXIT

awk -v pkg="$pkg_name" '
  /^[[:space:]]*IgnorePkg[[:space:]]*=/ {
    split($0, parts, "=")
    prefix = parts[1]
    n = split(parts[2], items, /[[:space:]]+/)
    out = ""
    for (i = 1; i <= n; i++) {
      if (items[i] == "" || items[i] == pkg) {
        continue
      }
      out = out (out ? " " : "") items[i]
    }
    print prefix "= " out
    next
  }
  { print }
' /etc/pacman.conf >"$tmp_config"

pacman_cmd=(pacman --config "$tmp_config" -S --noconfirm)
if [[ -z "$current_repo" ]]; then
  pacman_cmd+=(--needed)
fi
pacman_cmd+=("$pkg_spec")

if [[ "$(id -u)" -eq 0 ]]; then
  "${pacman_cmd[@]}"
else
  sudo "${pacman_cmd[@]}"
fi
