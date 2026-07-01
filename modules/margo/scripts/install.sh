#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
MODULE_DIR="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
REPO_ROOT="$(cd -- "${MODULE_DIR}/../.." && pwd)"
source "${REPO_ROOT}/modules/base/lib/core.sh"

# `.config/margo` + its subdirs: `layouts/` (mlayout layout snapshots) and
# `conf.d/` (margo config fragments — colors.conf / taglayouts.conf /
# mlayout.conf, written by matugen / mshell / mlayout and `source`d from
# config.conf). Pre-create them so the first source/symlink never races a
# missing parent.
if [ "$(id -u)" -eq 0 ]; then
	install -d -m0755 -o "${REAL_USER}" \
		"${USER_HOME}/.config/margo" \
		"${USER_HOME}/.config/margo/layouts" \
		"${USER_HOME}/.config/margo/conf.d" \
		"${USER_HOME}/.config/margo/twilight/presets" \
		"${USER_HOME}/.config/margo/mshell/profiles"
else
	mkdir -p \
		"${USER_HOME}/.config/margo/layouts" \
		"${USER_HOME}/.config/margo/conf.d" \
		"${USER_HOME}/.config/margo/twilight/presets" \
		"${USER_HOME}/.config/margo/mshell/profiles"
fi

if command -v systemctl >/dev/null 2>&1; then
	run_as_user systemctl --user daemon-reload >/dev/null 2>&1 || true
fi

# Cursor defaults for the greeter / pre-session, written to /etc/environment.
# (Folded in from the former wayland-env module; same managed-block markers so
# an existing block is updated in place, not duplicated.)
ENV_DST="/etc/environment"
MANAGED_BEGIN="# >>> mdots-wayland-env >>>"
MANAGED_END="# <<< mdots-wayland-env <<<"

write_etc_environment() {
	local sudo=""
	if [ "$(id -u)" -ne 0 ]; then
		if ! command -v sudo >/dev/null 2>&1; then
			log_warn "sudo yok; ${ENV_DST} cursor bloğu güncellenemedi"
			return 0
		fi
		sudo="sudo"
	fi

	local tmp new
	tmp="$(mktemp)"
	new="$(mktemp)"

	${sudo} test -f "${ENV_DST}" || ${sudo} install -m 644 /dev/null "${ENV_DST}"

	${sudo} awk -v begin="${MANAGED_BEGIN}" -v end="${MANAGED_END}" '
		$0 == begin { skip=1; next }
		$0 == end { skip=0; next }
		!skip { print }
	' "${ENV_DST}" >"${tmp}"

	{
		cat "${tmp}"
		printf '\n%s\n' "${MANAGED_BEGIN}"
		printf 'XCURSOR_THEME=capitaine-cursors\n'
		printf 'XCURSOR_SIZE=24\n'
		printf '%s\n' "${MANAGED_END}"
	} >"${new}"

	if ! ${sudo} cmp -s "${new}" "${ENV_DST}"; then
		${sudo} install -m 644 "${new}" "${ENV_DST}"
	fi

	rm -f "${tmp}" "${new}"
}

write_etc_environment
