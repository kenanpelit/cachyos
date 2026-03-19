#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
MODULE_DIR="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
PROFILE_MANIFEST="${MODULE_DIR}/monitors/profile.env"
PROFILES_DIR="${MODULE_DIR}/monitors/profiles"
MONITORS_OUT="${MODULE_DIR}/dotfiles/hypr/conf.d/70-monitors.conf"

usage() {
  cat <<'EOF'
Usage: render-monitors.sh [--check]

Without arguments, regenerates the managed Hyprland monitor routing file.
With --check, verifies that the generated file matches the selected profile.
EOF
}

mode="write"
case "${1:-}" in
  ""|--write)
    ;;
  --check)
    mode="check"
    ;;
  -h|--help)
    usage
    exit 0
    ;;
  *)
    usage >&2
    exit 2
    ;;
esac

# shellcheck source=/dev/null
source "${PROFILE_MANIFEST}"

: "${HYPR_MONITOR_PROFILE:=desk}"

PROFILE_FILE="${PROFILES_DIR}/${HYPR_MONITOR_PROFILE}.conf"
if [[ ! -r "${PROFILE_FILE}" ]]; then
  printf 'Unknown HYPR_MONITOR_PROFILE: %s\n' "${HYPR_MONITOR_PROFILE}" >&2
  exit 1
fi

manifest_checksum="$(sha256sum "${PROFILE_MANIFEST}" "${PROFILE_FILE}" | sha256sum | awk '{print $1}')"
tmp_out="$(mktemp)"

cleanup() {
  rm -f "${tmp_out}"
}
trap cleanup EXIT

{
  printf '# Generated from modules/hyprland/monitors/profile.env and monitors/profiles/%s.conf.\n' "${HYPR_MONITOR_PROFILE}"
  printf '# Update the manifest/profile and rerun modules/hyprland/scripts/render-monitors.sh.\n'
  printf '# Source checksum: %s\n\n' "${manifest_checksum}"
  printf '# Host profile: %s\n' "${HYPR_MONITOR_PROFILE}"
  cat "${PROFILE_FILE}"
} >"${tmp_out}"

if [[ "${mode}" == "check" ]]; then
  diff -u "${MONITORS_OUT}" "${tmp_out}"
  exit 0
fi

mv "${tmp_out}" "${MONITORS_OUT}"
