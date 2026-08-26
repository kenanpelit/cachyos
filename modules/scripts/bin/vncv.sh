#!/usr/bin/env bash
#
# vncv — TurboVNC viewer launcher (thin wrapper around VncViewer.jar)
#
# The bare `java -jar VncViewer.jar` invocation cannot find TurboVNC's JNI
# helper (libturbovnchelper.so) and warns on every connect, disabling:
#   - accelerated JPEG decompression
#   - keyboard grabbing / extended input / server-side keyboard mapping
#   - multi-screen spanning in full-screen mode
#
# The fix (mirroring upstream /usr/bin/vncviewer) is to point java at the
# dir holding the helper via -Djava.library.path, and to expose the JDK's
# libjawt.so (a runtime dependency of the helper) on LD_LIBRARY_PATH.
# --enable-native-access is kept so JDK 24+ does not flag the JNI load.
#
# Env overrides: JAVA_HOME, VNCV_JAVADIR (TurboVNC classes dir), JAVA_OPTS.
#
# Usage: vncv [viewer options] [host:display]
#   e.g. vncv -passwd ~/.vnc/passwd localhost:5901
#
set -euo pipefail

# --- java ---------------------------------------------------------------
JAVA="${JAVA_HOME:+$JAVA_HOME/bin/}java"
if ! command -v "$JAVA" >/dev/null 2>&1; then
	echo "vncv: java not found (install a JRE, or set JAVA_HOME)." >&2
	exit 1
fi

# --- TurboVNC classes dir (holds VncViewer.jar + libturbovnchelper.so) ---
TVNC_JAVADIR="${VNCV_JAVADIR:-}"
if [[ -z "$TVNC_JAVADIR" ]]; then
	for d in /usr/share/turbovnc/classes /opt/TurboVNC/java; do
		if [[ -f "$d/VncViewer.jar" ]]; then
			TVNC_JAVADIR="$d"
			break
		fi
	done
fi
if [[ -z "$TVNC_JAVADIR" || ! -f "$TVNC_JAVADIR/VncViewer.jar" ]]; then
	echo "vncv: VncViewer.jar not found (is turbovnc installed?)." >&2
	echo "vncv: set VNCV_JAVADIR to the dir containing VncViewer.jar." >&2
	exit 1
fi

# --- let the JNI helper resolve its libjawt.so dependency ---------------
# The helper is dlopen'd from java.library.path, but it in turn needs the
# JDK's libjawt.so; sun.boot.library.path points at the dir that holds it.
jawt_dir="$("$JAVA" -XshowSettings:properties -version 2>&1 |
	sed -n 's/.*sun\.boot\.library\.path = *//p' | head -n1)"
if [[ -n "$jawt_dir" && -f "$jawt_dir/libjawt.so" ]]; then
	export LD_LIBRARY_PATH="${jawt_dir}${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
fi

# JAVA_OPTS is deliberately left unquoted so it word-splits into separate
# JVM args; quoting would pass the whole string as one argument.
# shellcheck disable=SC2086
exec "$JAVA" \
	--enable-native-access=ALL-UNNAMED \
	-server \
	-Djava.library.path="$TVNC_JAVADIR" \
	${JAVA_OPTS:-} \
	-jar "$TVNC_JAVADIR/VncViewer.jar" "$@"
