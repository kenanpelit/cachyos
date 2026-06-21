#!/usr/bin/env bash
# Profile: helium-kenp (incognito)
#
# Thin wrapper around start-helium-kenp that opens the profile in a private /
# incognito window. profile_helium runs it as its own isolated instance
# (user-data-dir + window class "Kenp_incognito"), so it never touches a normal
# start-helium-kenp session. Any extra args pass straight through to the browser.
exec start-helium-kenp --incognito "$@"
