#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: mango-tag-smart <tag>

Move the focused window to the requested tag's home monitor using MangoWM's
generated profile metadata.
EOF
}

[[ $# -eq 1 ]] || {
  usage >&2
  exit 2
}

tag="$1"

[[ "${tag}" =~ ^[1-9]$ ]] || {
  echo "tag must be between 1 and 9" >&2
  exit 2
}

command -v mmsg >/dev/null 2>&1 || {
  echo "mmsg is required" >&2
  exit 1
}

profile_candidates=(
  "${XDG_CONFIG_HOME:-${HOME}/.config}/mango/runtime/profile.conf"
  "${XDG_CONFIG_HOME:-${HOME}/.config}/mango/generated/profile.conf"
  "/etc/xdg/mango/runtime/profile.conf"
  "/etc/xdg/mango/generated/profile.conf"
)

profile_file=""
for candidate in "${profile_candidates[@]}"; do
  if [[ -r "${candidate}" ]]; then
    profile_file="${candidate}"
    break
  fi
done

[[ -n "${profile_file}" ]] || {
  echo "unable to locate Mango runtime profile.conf" >&2
  exit 1
}

monitor="$(
  awk -F',' -v tag="${tag}" '
    $0 ~ "^tagrule=id:" tag "," {
      for (i = 1; i <= NF; i++) {
        if ($i ~ /^monitor_name:/) {
          sub(/^monitor_name:/, "", $i)
          print $i
          exit
        }
      }
    }
  ' "${profile_file}"
)"

[[ -n "${monitor}" ]] || {
  echo "unable to resolve monitor for tag ${tag}" >&2
  exit 1
}

exec mmsg -d "tagcrossmon,${tag},${monitor}"
