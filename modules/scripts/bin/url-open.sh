#!/usr/bin/env bash
# url-open — open URL(s) as a tab in the running *default* browser.
#
# Follows $BROWSER, so it keeps working when the default browser changes
# (brave → helium → firefox → …) with no other edits. The heavy Semsumo session
# launchers (start-<engine>-<profile>) ignore their URL argument, so map them to
# the matching lightweight profile launcher, which hands the URL to the already
# running isolated instance as a new tab instead of spawning a fresh window.
#
# Resolution order (first that resolves wins; falls through otherwise):
#   $BROWSER = start-<engine>-<profile>
#       1) profile_<engine> <profile> --separate --new-tab <url>   # chromium: brave/helium
#       2) <engine> <url>                                          # e.g. firefox
#   $BROWSER = <command>   → <command> <url>                       # plain firefox/brave/…
#   (nothing resolved)     → xdg-open <url>                        # desktop default
set -euo pipefail

# exec the command if it exists on PATH; otherwise return 0 so we can fall
# through to the next strategy (exec only returns here on failure).
try() { command -v "$1" >/dev/null 2>&1 && exec "$@"; return 0; }

browser="${BROWSER:-}"

case "$browser" in
	start-*-*)
		rest="${browser#start-}"   # <engine>-<profile…>
		engine="${rest%%-*}"       # brave | helium | firefox | …
		profile="${rest#*-}"       # kenp | ai | …
		try "profile_${engine}" "$profile" --separate --new-tab "$@"
		try "$engine" "$@"
		;;
	?*)
		try "$browser" "$@"
		;;
esac

exec xdg-open "$@"
