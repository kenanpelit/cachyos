#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
MODULE_DIR="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
REPO_ROOT="$(cd -- "${MODULE_DIR}/../.." && pwd)"
source "${REPO_ROOT}/modules/base/lib/core.sh"

MAKEPKG_CONF="${MAKEPKG_CONF:-/etc/makepkg.conf}"
CCACHE_MAX_SIZE="${MAKEPKG_CCACHE_MAX_SIZE:-100G}"
CCACHE_CONFIG_DIR="${XDG_CONFIG_HOME:-${USER_HOME}/.config}/ccache"
CCACHE_CONFIG_FILE="${CCACHE_CONFIG_DIR}/ccache.conf"

SUDO=()
if [[ "$(id -u)" -ne 0 ]]; then
	if ! command -v sudo >/dev/null 2>&1; then
		die "sudo is required to update ${MAKEPKG_CONF}"
	fi
	SUDO=(sudo)
fi

configure_makepkg_ccache() {
	[[ -r "${MAKEPKG_CONF}" ]] || die "makepkg.conf not found: ${MAKEPKG_CONF}"
	command -v python3 >/dev/null 2>&1 || die "python3 is required"

	local tmp
	tmp="$(mktemp)"
	python3 - "${MAKEPKG_CONF}" "${tmp}" <<'PY'
import re
import sys
from pathlib import Path

source = Path(sys.argv[1])
target = Path(sys.argv[2])
text = source.read_text()


def normalize_buildenv(match):
    raw = match.group(1)
    tokens = raw.split()
    normalized = []
    saw_ccache = False

    for token in tokens:
        if token.lstrip("!") == "ccache":
            normalized.append("ccache")
            saw_ccache = True
        else:
            normalized.append(token)

    if not saw_ccache:
        insert_at = normalized.index("check") if "check" in normalized else len(normalized)
        normalized.insert(insert_at, "ccache")

    return "BUILDENV=(" + " ".join(normalized) + ")"


pattern = re.compile(r"^BUILDENV=\(([^)]*)\)$", re.MULTILINE)
if pattern.search(text):
    text = pattern.sub(normalize_buildenv, text, count=1)
else:
    text = text.rstrip() + "\n\n# Managed by modules/makepkg/scripts/install.sh\nBUILDENV=(!distcc color ccache check !sign)\n"

target.write_text(text)
PY

	if ! cmp -s "${tmp}" "${MAKEPKG_CONF}"; then
		"${SUDO[@]}" install -m 644 "${tmp}" "${MAKEPKG_CONF}"
	fi
	rm -f "${tmp}"
}

configure_ccache_limit() {
	run_as_user install -d -m 755 "${CCACHE_CONFIG_DIR}"

	local tmp
	tmp="$(mktemp)"
	python3 - "${CCACHE_CONFIG_FILE}" "${tmp}" "${CCACHE_MAX_SIZE}" <<'PY'
import re
import sys
from pathlib import Path

source = Path(sys.argv[1])
target = Path(sys.argv[2])
max_size = sys.argv[3]

lines = source.read_text().splitlines() if source.exists() else []
pattern = re.compile(r"^\s*max_size\s*=")
updated = False
result = []

for line in lines:
    if pattern.match(line):
        result.append(f"max_size = {max_size}")
        updated = True
    else:
        result.append(line)

if not updated:
    if result and result[-1].strip():
        result.append("")
    result.append("# Managed by modules/makepkg/scripts/install.sh")
    result.append(f"max_size = {max_size}")

target.write_text("\n".join(result).rstrip() + "\n")
PY

	run_as_user install -m 644 "${tmp}" "${CCACHE_CONFIG_FILE}"
	rm -f "${tmp}"

	if command -v ccache >/dev/null 2>&1; then
		run_as_user ccache --max-size="${CCACHE_MAX_SIZE}" >/dev/null
	fi
}

configure_makepkg_ccache
configure_ccache_limit

log_success "makepkg ccache is enabled with max_size=${CCACHE_MAX_SIZE}"
