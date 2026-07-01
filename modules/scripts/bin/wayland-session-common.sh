#!/usr/bin/env bash
# ==============================================================================
# Script: wayland-session-common.sh
# Description: Shared env parsing and runtime-dir helpers for Wayland sessions.
# Usage: source wayland-session-common.sh   # library — do not execute directly
# ==============================================================================
# ⚠️  CRITICAL SHARED LIBRARY — DO NOT DELETE.
#
#   This is load-bearing infrastructure for the whole session-launch stack.
#   It is sourced by ~80 callers: every modules/scripts/start/start-* launcher
#   (brave/helium/firefox/telegram/spotify/kkenp/…) plus semsumo.sh,
#   semsumo-daily.sh, margo-semsumo-daily.sh, margo-session-common.sh and
#   delayed-portals.sh. They rely on the public session_common_* function
#   names below to set up PATH/XDG dirs, cursor/theme env, and the Wayland
#   display before spawning apps under uwsm/systemd.
#
#   Rules of thumb:
#     • Keep the session_common_* function names/signatures stable — renaming
#       or removing one silently breaks dozens of launchers.
#     • Never add `set -e`/`set -u` or top-level side effects: this file is
#       SOURCED, so any such change leaks into every caller's shell.
#     • Add new helpers rather than repurposing existing ones.
#
# Function library — it only defines session_common_* helpers and runs no
# top-level logic. Re-sourcing it in the same shell is a no-op.

# Refuse to run as a standalone program — it only makes sense when sourced.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
	printf '%s is a library; source it, do not execute it.\n' \
		"${BASH_SOURCE[0]##*/}" >&2
	exit 64 # EX_USAGE
fi

# Idempotent include guard: skip re-defining functions if already sourced.
[[ -n "${_WAYLAND_SESSION_COMMON_SOURCED:-}" ]] && return 0
_WAYLAND_SESSION_COMMON_SOURCED=1

session_common_log_warn() {
	printf '[wayland-session-common] WARN: %s\n' "$*" >&2
}

session_common_ensure_runtime_dir() {
	if [[ -z "${XDG_RUNTIME_DIR:-}" ]]; then
		export XDG_RUNTIME_DIR="/run/user/$(id -u)"
	fi
}

session_common_expand_env_value() {
	local value="$1"
	local expanded prefix var_name suffix var_value
	local guard=0
	local -r max_iter=64 # bound expansion so a self-referential value can't hang

	expanded="$value"

	while [[ "$expanded" =~ (.*)\$\{([A-Za-z_][A-Za-z0-9_]*)\}(.*) ]]; do
		if ((++guard > max_iter)); then
			session_common_log_warn "env value did not converge, leaving as-is: ${value}"
			break
		fi
		prefix="${BASH_REMATCH[1]}"
		var_name="${BASH_REMATCH[2]}"
		suffix="${BASH_REMATCH[3]}"
		var_value="${!var_name-}"
		expanded="${prefix}${var_value}${suffix}"
	done

	guard=0
	while [[ "$expanded" =~ (.*)\$([A-Za-z_][A-Za-z0-9_]*)(.*) ]]; do
		if ((++guard > max_iter)); then
			session_common_log_warn "env value did not converge, leaving as-is: ${value}"
			break
		fi
		prefix="${BASH_REMATCH[1]}"
		var_name="${BASH_REMATCH[2]}"
		suffix="${BASH_REMATCH[3]}"
		var_value="${!var_name-}"
		expanded="${prefix}${var_value}${suffix}"
	done

	printf '%s\n' "$expanded"
}

session_common_parse_env_file() {
	local env_file="$1"
	local line key value expanded_value

	[[ -r "$env_file" ]] || return 0

	while IFS= read -r line; do
		line="${line#"${line%%[![:space:]]*}"}"
		line="${line%"${line##*[![:space:]]}"}"
		[[ -n "$line" ]] || continue
		[[ "${line#\#}" == "$line" ]] || continue

		if [[ "$line" == export[[:space:]]* ]]; then
			line="${line#export }"
			line="${line#"${line%%[![:space:]]*}"}"
		fi

		if [[ "$line" != *=* ]]; then
			session_common_log_warn "ignoring unsupported env line in ${env_file}: ${line}"
			continue
		fi

		key="${line%%=*}"
		value="${line#*=}"
		key="${key#"${key%%[![:space:]]*}"}"
		key="${key%"${key##*[![:space:]]}"}"
		[[ -n "$key" ]] || continue
		if [[ ! "$key" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]; then
			session_common_log_warn "ignoring invalid env key in ${env_file}: ${key}"
			continue
		fi
		if [[ "$value" == \"*\" && "$value" == *\" ]]; then
			value="${value:1:${#value}-2}"
		elif [[ "$value" == \'*\' && "$value" == *\' ]]; then
			value="${value:1:${#value}-2}"
		fi
		expanded_value="$(session_common_expand_env_value "$value")"
		export "$key=$expanded_value"
		printf '%s=%s\n' "$key" "$expanded_value"
	done <"$env_file"
}

session_common_parse_env_dir() {
	local file

	for file in "$@"; do
		[[ -r "$file" ]] || continue
		session_common_parse_env_file "$file"
	done
}

session_common_load_session_env() {
	local collector="$1"
	local kv key value

	while IFS= read -r kv; do
		key="${kv%%=*}"
		value="${kv#*=}"
		[[ -n "$key" ]] || continue
		export "$key=$value"
	done < <("$collector")
}

session_common_normalize_colon_list() {
	local value="$1"
	local expanded part
	local -a parts cleaned=()
	local -A seen=()
	local IFS # scope IFS to this function so ':' never leaks back to the caller

	expanded="${value//\$\{HOME\}/$HOME}"
	expanded="${expanded//\$HOME/$HOME}"
	IFS=':' read -r -a parts <<<"$expanded"

	for part in "${parts[@]}"; do
		[[ -n "$part" ]] || continue
		[[ -n "${seen[$part]:-}" ]] && continue
		seen["$part"]=1
		cleaned+=("$part")
	done

	IFS=':'
	printf '%s\n' "${cleaned[*]}"
}

session_common_normalize_session_paths() {
	local default_path default_data_dirs

	default_path="${HOME}/.local/bin:${HOME}/bin:/usr/local/bin:/usr/bin:/bin:/usr/local/sbin:${HOME}/.local/share/flatpak/exports/bin:/var/lib/flatpak/exports/bin:/usr/lib/jvm/default/bin:/usr/bin/site_perl:/usr/bin/vendor_perl:/usr/bin/core_perl"
	PATH="$(session_common_normalize_colon_list "${PATH:-$default_path}")"
	export PATH

	default_data_dirs="${HOME}/.local/share/flatpak/exports/share:/var/lib/flatpak/exports/share:/usr/local/share:/usr/share"
	XDG_DATA_DIRS="$(session_common_normalize_colon_list "${XDG_DATA_DIRS:-$default_data_dirs}")"
	export XDG_DATA_DIRS

	export XDG_CONFIG_DIRS="${XDG_CONFIG_DIRS:-/etc/xdg}"
}

session_common_backfill_visual_env() {
	local kv key value
	local config_home env_dir session_env_file=""

	if [[ -n "${XCURSOR_THEME:-}" && "${XCURSOR_THEME}" != "default" && -n "${XCURSOR_SIZE:-}" ]]; then
		return 0
	fi

	if command -v systemctl >/dev/null 2>&1; then
		while IFS= read -r kv; do
			[[ "$kv" == *=* ]] || continue
			key="${kv%%=*}"
			value="${kv#*=}"
			case "$key" in
			XCURSOR_THEME | XCURSOR_SIZE | GTK_THEME | XDG_ICON_THEME | QT_ICON_THEME | QT_QPA_PLATFORMTHEME | QT_QPA_PLATFORMTHEME_QT6 | QT_STYLE_OVERRIDE)
				[[ -n "$value" ]] && export "$key=$value"
				;;
			esac
		done < <(systemctl --user show-environment 2>/dev/null || true)
	fi

	if [[ -z "${XCURSOR_THEME:-}" || "${XCURSOR_THEME}" == "default" ]]; then
		config_home="${XDG_CONFIG_HOME:-$HOME/.config}"
		env_dir="${config_home}/environment.d"

		case "${XDG_CURRENT_DESKTOP:-}" in
		*[Mm]argo*)
			session_env_file="${config_home}/environment.d/10-margo-wayland.conf"
			;;
		*)
			# Generic Wayland fallback: no compositor-specific env file;
			# the shared 10-gtk/20-qt files below still apply.
			session_env_file=""
			;;
		esac

		while IFS= read -r kv; do
			[[ "$kv" == *=* ]] || continue
			key="${kv%%=*}"
			value="${kv#*=}"
			case "$key" in
			XCURSOR_THEME | XCURSOR_SIZE | GTK_THEME | XDG_ICON_THEME | QT_ICON_THEME | QT_QPA_PLATFORMTHEME | QT_QPA_PLATFORMTHEME_QT6 | QT_STYLE_OVERRIDE)
				[[ -n "$value" ]] && export "$key=$value"
				;;
			esac
		done < <(
			session_common_parse_env_dir \
				"${env_dir}/10-gtk.conf" \
				"${env_dir}/20-qt.conf" \
				"${session_env_file}"
		)
	fi

	if [[ -z "${XCURSOR_THEME:-}" || "${XCURSOR_THEME}" == "default" ]]; then
		export XCURSOR_THEME="capitaine-cursors"
	fi

	export XCURSOR_SIZE="${XCURSOR_SIZE:-24}"
}

session_common_detect_wayland_display() {
	[[ -n "${WAYLAND_DISPLAY:-}" ]] && return 0
	[[ -n "${XDG_RUNTIME_DIR:-}" ]] || return 0

	local sock
	for sock in "${XDG_RUNTIME_DIR}"/wayland-*; do
		[[ -S "$sock" ]] || continue
		export WAYLAND_DISPLAY
		WAYLAND_DISPLAY="$(basename "$sock")"
		return 0
	done
}

session_common_detect_x11_display() {
	[[ -n "${DISPLAY:-}" ]] && return 0

	local sock candidate display
	local -a candidates=()

	shopt -s nullglob
	for sock in /tmp/.X11-unix/X*; do
		[[ -S "$sock" ]] || continue
		candidates+=("$sock")
	done
	shopt -u nullglob

	[[ ${#candidates[@]} -gt 0 ]] || return 0

	candidate="${candidates[0]}"
	if [[ ${#candidates[@]} -gt 1 ]]; then
		candidate="$(ls -1t /tmp/.X11-unix/X* 2>/dev/null | head -n 1 || true)"
		[[ -n "${candidate:-}" ]] || candidate="${candidates[0]}"
		session_common_log_warn "multiple X11 displays detected; using ${candidate}"
	fi

	display="$(basename "${candidate}")"
	display=":${display#X}"
	export DISPLAY="${display}"
}

session_common_under_uwsm() {
	[[ -n "${UWSM_ID:-}" ]] ||
		[[ -n "${UWSM_FINALIZE_VARNAMES:-}" ]] ||
		[[ -n "${UWSM_WAIT_VARNAMES:-}" ]] ||
		[[ "${DESKTOP_SESSION:-}" == *-uwsm* ]]
}

session_common_sync_environment_vars() {
	local collector="$1"
	local -a env_vars=()
	local -a set_args=()
	local var value

	while IFS= read -r var; do
		[[ -n "$var" ]] || continue
		value="${!var-}"
		[[ -n "$value" ]] || continue
		env_vars+=("$var")
		set_args+=("${var}=${value}")
	done < <("$collector")

	[[ ${#env_vars[@]} -gt 0 ]] || return 0

	if command -v systemctl >/dev/null 2>&1; then
		systemctl --user import-environment "${env_vars[@]}" >/dev/null 2>&1 || true
		systemctl --user set-environment "${set_args[@]}" >/dev/null 2>&1 || true
	fi

	if command -v dbus-update-activation-environment >/dev/null 2>&1; then
		dbus-update-activation-environment --systemd "${env_vars[@]}" >/dev/null 2>&1 ||
			dbus-update-activation-environment --systemd --all >/dev/null 2>&1 ||
			true
	fi
}

session_common_unset_manager_env() {
	[[ $# -gt 0 ]] || return 0
	command -v systemctl >/dev/null 2>&1 || return 0
	systemctl --user unset-environment "$@" >/dev/null 2>&1 || true
}

session_common_set_manager_env() {
	[[ $# -gt 0 ]] || return 0
	command -v systemctl >/dev/null 2>&1 || return 0
	systemctl --user set-environment "$@" >/dev/null 2>&1 || true
}
