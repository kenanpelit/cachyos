#!/usr/bin/env bash
# url-open — open URL(s) as a new TAB in the running *default* browser instance.
#
# Follows $BROWSER, so it keeps working when the default browser changes
# (brave → helium → firefox → …). For the Semsumo session launchers
# (start-<engine>-<profile>) it hands the URL to the already-running isolated
# instance by replaying that instance's --user-data-dir/--profile-directory with
# a freshly-resolved engine binary — chromium then opens the link as a tab in the
# existing window instead of a new window. If nothing is running it starts the
# browser; non-chromium engines (firefox) and plain commands open directly; the
# last resort is xdg-open.
#
# Resolution order ($BROWSER = start-<engine>-<profile>):
#   1) running chromium instance for <profile> → replay its data-dir/profile  (TAB)
#   2) profile_<engine> <profile> --separate <url>                            (start it)
#   3) <engine> <url>                                                         (e.g. firefox)
# $BROWSER = <command>  → <command> <url>      ·  nothing → xdg-open <url>
set -euo pipefail

# exec the command if it exists; otherwise return 0 to fall through.
try() { command -v "$1" >/dev/null 2>&1 && exec "$@"; return 0; }

# Resolve a chromium-family browser binary for <engine> (brave/helium/…).
resolve_bin() {
	local engine="$1" c
	for c in "${engine}-origin-beta" "${engine}-browser" "${engine}-origin" "${engine}-bin" "${engine}"; do
		if command -v "$c" >/dev/null 2>&1; then
			command -v "$c"
			return 0
		fi
	done
	return 1
}

# If a chromium-family browser is already running for this isolated profile,
# replay its --user-data-dir/--profile-directory (read from `ps`) with a resolved
# engine binary and the URL appended, so it opens as a tab in that window.
# Returns 1 if no such instance is running. NOTE: the binary is resolved from the
# engine name, NOT taken from ps argv[0] — the launcher there is a shell wrapper
# (e.g. `/bin/bash …/brave-origin`), so argv[0] is the shell, not the browser.
open_existing_tab() {
	local engine="$1" profile="$2"
	shift 2
	local line udd pdir bin
	line="$(ps -eo args= 2>/dev/null \
		| grep -E -- "--user-data-dir=[^ ]*/${profile}([ ]|\$)" \
		| grep -v -- '--type=' \
		| head -n1 || true)"
	[ -n "$line" ] || return 1
	udd="$(printf '%s\n' "$line" | grep -oE -- '--user-data-dir=[^ ]+' | head -n1)"
	pdir="$(printf '%s\n' "$line" | grep -oE -- '--profile-directory=[^ ]+' | head -n1 || true)"
	[ -n "$udd" ] || return 1
	bin="$(resolve_bin "$engine")" || return 1
	exec "$bin" "$udd" ${pdir:+"$pdir"} "$@"
}

browser="${BROWSER:-}"

case "$browser" in
	start-*-*)
		rest="${browser#start-}" # <engine>-<profile…>
		engine="${rest%%-*}"     # brave | helium | firefox | …
		profile="${rest#*-}"     # kenp | ai | …
		open_existing_tab "$engine" "$profile" "$@" || true
		try "profile_${engine}" "$profile" --separate "$@"
		try "$engine" "$@"
		;;
	?*)
		try "$browser" "$@"
		;;
esac

exec xdg-open "$@"
