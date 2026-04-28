#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
MODULE_DIR="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
MANIFEST="${MODULE_DIR}/theme/theme.env"
PACKAGES_OUT="${MODULE_DIR}/packages.yaml"

usage() {
	cat <<'EOF'
Usage: render-packages.sh [--check]

Without arguments, regenerates packages.yaml from theme/theme.env.
With --check, verifies that packages.yaml matches the selected package variant.
EOF
}

mode="write"
case "${1:-}" in
"" | --write)
	;;
--check)
	mode="check"
	;;
-h | --help)
	usage
	exit 0
	;;
*)
	usage >&2
	exit 2
	;;
esac

# shellcheck source=/dev/null
source "${MANIFEST}"

manifest_checksum="$(sha256sum "${MANIFEST}" | awk '{print $1}')"
package_variant="${MANGO_PACKAGE_VARIANT:-full}"

case "${package_variant}" in
full | full-git)
	compositor_package="mangowm-git"
	;;
full-stable)
	compositor_package="mangowm"
	;;
wlonly | wlonly-git)
	compositor_package="mangowm-wlonly-git"
	;;
wlonly-stable)
	compositor_package="mangowm-wlonly"
	;;
*)
	echo "Unknown MANGO_PACKAGE_VARIANT: ${package_variant}" >&2
	exit 1
	;;
esac

tmp_packages="$(mktemp)"
cleanup() {
	rm -f "${tmp_packages}"
}
trap cleanup EXIT

cat >"${tmp_packages}" <<EOF
# Generated from modules/mangowm/theme/theme.env.
# Update the manifest and rerun modules/mangowm/scripts/render-packages.sh.
# Source checksum: ${manifest_checksum}
# Package variant: ${package_variant}

description: MangoWM packages

packages:
  - ${compositor_package}
  - uwsm
  - polkit-gnome
  - network-manager-applet
  - xdg-desktop-portal-wlr
  # portals.conf routes Secret to gnome-keyring.
  - gnome-keyring
  - wl-clipboard
  - wl-clip-persist
  - cliphist
  - brightnessctl
  - jq
  - wlr-randr
  - grim
  - slurp
EOF

if [[ "${mode}" == "check" ]]; then
	diff -u "${PACKAGES_OUT}" "${tmp_packages}"
	exit 0
fi

install -D -m 644 "${tmp_packages}" "${PACKAGES_OUT}"
