#!/usr/bin/env bash
set -euo pipefail

PROFILE_FILE="${MANGO_PROFILE_FILE:-}"

usage() {
	cat <<'EOF'
Usage: mango-monitor-smart {focus-next|move-next}

focus-next  Focus the next monitor in the active MangoWM profile order.
move-next   Move the focused window to the next monitor and keep its tag.
EOF
}

[[ $# -eq 1 ]] || {
	usage >&2
	exit 2
}

command -v mmsg >/dev/null 2>&1 || {
	echo "mmsg is required" >&2
	exit 1
}

if [[ -z "${PROFILE_FILE}" ]]; then
	for candidate in \
		"${XDG_CONFIG_HOME:-$HOME/.config}/mango/generated/profile.conf" \
		"${XDG_CONFIG_HOME:-$HOME/.config}/mango/runtime/profile.conf" \
		"/etc/xdg/mango/generated/profile.conf" \
		"/etc/xdg/mango/runtime/profile.conf"; do
		if [[ -r "${candidate}" ]]; then
			PROFILE_FILE="${candidate}"
			break
		fi
	done
fi

[[ -r "${PROFILE_FILE}" ]] || {
	echo "Mango profile file not found" >&2
	exit 1
}

mapfile -t monitors < <(
	awk -F',' '
    /^monitorrule=/ {
      for (i = 1; i <= NF; i++) {
        if ($i ~ /^monitorrule=name:\^/) {
          name = $i
          sub(/^monitorrule=name:\^/, "", name)
          sub(/\$$/, "", name)
          print name
        }
      }
    }
  ' "${PROFILE_FILE}"
)

((${#monitors[@]} > 0)) || {
	echo "No monitors found in ${PROFILE_FILE}" >&2
	exit 1
}

current_monitor="$(
	mmsg -g -o 2>/dev/null | awk '$2 == "selmon" && $3 == "1" { print $1; exit }'
)"

[[ -n "${current_monitor}" ]] || current_monitor="${monitors[0]}"

next_monitor="${monitors[0]}"
for i in "${!monitors[@]}"; do
	if [[ "${monitors[$i]}" == "${current_monitor}" ]]; then
		next_monitor="${monitors[$(((i + 1) % ${#monitors[@]}))]}"
		break
	fi
done

case "$1" in
focus-next)
	exec mmsg -d "focusmon,${next_monitor}"
	;;
move-next)
	exec mmsg -d "tagmon,${next_monitor},1"
	;;
*)
	usage >&2
	exit 2
	;;
esac
