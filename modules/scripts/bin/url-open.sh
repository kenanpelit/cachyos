#!/usr/bin/env bash
# url-open — open URL(s) as a new TAB in the running *default* browser instance.
#
# Follows $BROWSER, so it keeps working when the default browser changes
# (brave → helium → firefox → …). For the Semsumo session launchers
# (start-<engine>-<profile>) it hands the URL to the already-running isolated
# instance by replaying that process's own --user-data-dir/--profile-directory —
# chromium then opens the link as a tab in the existing window instead of a new
# window. If nothing is running it starts the browser; non-chromium engines
# (firefox) and plain commands open the URL directly; last resort is xdg-open.
#
# Resolution order ($BROWSER = start-<engine>-<profile>):
#   1) running chromium instance for <profile> → replay its flags    (TAB)
#   2) profile_<engine> <profile> --separate <url>                   (start it)
#   3) <engine> <url>                                                (e.g. firefox)
# $BROWSER = <command>  → <command> <url>      ·  nothing → xdg-open <url>
set -euo pipefail

# exec the command if it exists; otherwise return 0 to fall through.
try() { command -v "$1" >/dev/null 2>&1 && exec "$@"; return 0; }

# Replay a running chromium-family instance for this isolated profile (reuse its
# exact binary + data-dir + profile-directory) so the URL opens as a tab in that
# window. Returns 1 if no such instance is running.
open_existing_tab() {
	local profile="$1"
	shift
	local line bin udd pdir
	# The main browser process: --user-data-dir=…/<profile>, not a --type= child.
	line="$(ps -eo args= 2>/dev/null \
		| grep -E -- "--user-data-dir=[^ ]*/${profile}([ ]|\$)" \
		| grep -v -- '--type=' \
		| head -n1 || true)"
	[ -n "$line" ] || return 1
	bin="${line%% *}"
	udd="$(printf '%s\n' "$line" | grep -oE -- '--user-data-dir=[^ ]+' | head -n1)"
	pdir="$(printf '%s\n' "$line" | grep -oE -- '--profile-directory=[^ ]+' | head -n1 || true)"
	[ -n "$bin" ] && [ -n "$udd" ] || return 1
	command -v "$bin" >/dev/null 2>&1 || bin="$(command -v "$(basename "$bin")" 2>/dev/null || echo "$bin")"
	exec "$bin" "$udd" ${pdir:+"$pdir"} "$@"
}

browser="${BROWSER:-}"

case "$browser" in
	start-*-*)
		rest="${browser#start-}" # <engine>-<profile…>
		engine="${rest%%-*}"     # brave | helium | firefox | …
		profile="${rest#*-}"     # kenp | ai | …
		open_existing_tab "$profile" "$@" || true
		try "profile_${engine}" "$profile" --separate "$@"
		try "$engine" "$@"
		;;
	?*)
		try "$browser" "$@"
		;;
esac

exec xdg-open "$@"
