#!/usr/bin/env bash
set -euo pipefail

SCRIPT_NAME="$(basename "$0")"

if [[ -t 1 ]]; then
	GRN=$'\033[0;32m'
	YLW=$'\033[0;33m'
	RED=$'\033[0;31m'
	CYN=$'\033[0;36m'
	DIM=$'\033[0;2m'
	RST=$'\033[0m'
else
	GRN='' YLW='' RED='' CYN='' DIM='' RST=''
fi

have() { command -v "$1" >/dev/null 2>&1; }

hr() { printf "%s\n" "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"; }

print_kv() {
	local key="$1"
	shift
	printf "%s%s:%s %s\n" "${CYN}" "$key" "${RST}" "$*"
}

get_nameservers() {
	# Parse /etc/resolv.conf in a conservative way.
	# Only prints the IP/host part after "nameserver".
	[[ -r /etc/resolv.conf ]] || return 0
	awk '$1=="nameserver"{print $2}' /etc/resolv.conf 2>/dev/null || true
}

is_loopback_resolver() {
	local ns="${1:-}"
	case "$ns" in
	127.* | ::1 | localhost) return 0 ;;
	*) return 1 ;;
	esac
}

is_active() {
	local unit="$1"
	have systemctl || return 1
	systemctl is-active --quiet "$unit" 2>/dev/null
}

join_by() {
	local sep="$1"
	shift
	local out=''
	local item
	for item in "$@"; do
		if [[ -z "$out" ]]; then
			out="$item"
		else
			out="${out}${sep}${item}"
		fi
	done
	printf "%s" "$out"
}

DIG_STATUS=''
DIG_VALUE=''
DIG_RAW=''
DEFAULT_STATUS=''
DEFAULT_VALUE=''
DEFAULT_RAW=''
RESOLVECTL_OK=0
RESOLVECTL_ERROR=''
RESOLVECTL_DNS_RAW=''
RESOLVECTL_SERVERS=''
RESOLVECTL_CURRENT=''
RESOLVECTL_STATUS_RAW=''
RESOLVECTL_DNS_LINKS=''
RESOLVECTL_LINK_DNS=''

dig_probe() {
	# Sets globals: DIG_STATUS, DIG_VALUE, DIG_RAW
	# DIG_STATUS: ok | noanswer | refused | timeout | error | nodig
	# DIG_VALUE: last answer line (usually an IP, when available)
	local server="$1"
	local name="$2"
	local qtype="${3:-A}"

	DIG_STATUS='error'
	DIG_VALUE=''
	DIG_RAW=''

	if ! have dig; then
		DIG_STATUS='nodig'
		return 0
	fi

	local raw rc
	set +e
	if [[ -n "$server" ]]; then
		raw="$(dig @"$server" "$name" "$qtype" +tries=1 +timeout=2 +short 2>&1)"
		rc=$?
	else
		raw="$(dig "$name" "$qtype" +tries=1 +timeout=2 +short 2>&1)"
		rc=$?
	fi
	set -e

	DIG_RAW="$raw"

	if [[ "$rc" -ne 0 ]]; then
		if printf '%s\n' "$raw" | command grep -qi 'connection refused'; then
			DIG_STATUS='refused'
			return 0
		fi
		if printf '%s\n' "$raw" | command grep -Eqi 'timed out|no servers could be reached'; then
			DIG_STATUS='timeout'
			return 0
		fi
		DIG_STATUS='error'
		return 0
	fi

	# dig prints errors and even the command header to STDOUT on failures (even with +short).
	# Drop comment-like lines (starting with ';') and blanks.
	local filtered
	filtered="$(printf '%s\n' "$raw" | sed -e '/^[;].*/d' -e '/^$/d' || true)"

	if [[ -n "$filtered" ]]; then
		DIG_STATUS='ok'
		DIG_VALUE="$(printf '%s\n' "$filtered" | tail -n 1 | head -n 1)"
		return 0
	fi

	DIG_STATUS='noanswer'
}

default_probe() {
	# Prefer libc resolver path here so local loopback stubs do not hit dig/libuv bugs.
	DEFAULT_STATUS='error'
	DEFAULT_VALUE=''
	DEFAULT_RAW=''

	if have getent; then
		local raw rc
		set +e
		raw="$(getent ahostsv4 example.com 2>&1)"
		rc=$?
		set -e

		DEFAULT_RAW="$raw"
		if [[ "$rc" -eq 0 ]]; then
			DEFAULT_STATUS='ok'
			DEFAULT_VALUE="$(printf '%s\n' "$raw" | awk 'NR==1{print $1; exit}')"
			return 0
		fi

		if [[ -z "$raw" ]]; then
			DEFAULT_STATUS='noanswer'
			return 0
		fi
	fi

	dig_probe "" example.com A
	DEFAULT_STATUS="$DIG_STATUS"
	DEFAULT_VALUE="$DIG_VALUE"
	DEFAULT_RAW="$DIG_RAW"
}

collect_resolvectl_state() {
	RESOLVECTL_OK=0
	RESOLVECTL_ERROR=''
	RESOLVECTL_DNS_RAW=''
	RESOLVECTL_SERVERS=''
	RESOLVECTL_CURRENT=''
	RESOLVECTL_STATUS_RAW=''
	RESOLVECTL_DNS_LINKS=''
	RESOLVECTL_LINK_DNS=''

	have resolvectl || return 0

	local dns_raw dns_rc
	set +e
	dns_raw="$(resolvectl dns 2>&1)"
	dns_rc=$?
	set -e

	if [[ "$dns_rc" -ne 0 ]]; then
		RESOLVECTL_ERROR="$dns_raw"
		return 0
	fi

	RESOLVECTL_DNS_RAW="$dns_raw"
	RESOLVECTL_SERVERS="$(
		printf '%s\n' "$dns_raw" |
			sed -E 's/^Link [0-9]+ \([^)]*\):[[:space:]]*//' |
			tr '\n' ' ' |
			sed -E 's/[[:space:]]+/ /g; s/[[:space:]]+$//'
	)"

	local status_raw status_rc
	set +e
	status_raw="$(resolvectl status 2>&1)"
	status_rc=$?
	set -e

	if [[ "$status_rc" -eq 0 ]]; then
		RESOLVECTL_STATUS_RAW="$status_raw"
		RESOLVECTL_CURRENT="$(
			printf '%s\n' "$status_raw" |
				awk -F': ' '/Current DNS Server:/ {print $2}' |
				paste -sd', ' -
		)"
		RESOLVECTL_DNS_LINKS="$(
			printf '%s\n' "$status_raw" |
				awk '
					match($0, /^Link [0-9]+ \(([^)]+)\)/, m) { cur = m[1]; next }
					/^[[:space:]]*Current Scopes:/ {
						if (cur != "" && $0 ~ /DNS/) {
							if (seen[cur] != 1) {
								seen[cur] = 1
								if (out == "") out = cur
								else out = out ", " cur
							}
						}
					}
					END { print out }
				'
		)"
		RESOLVECTL_LINK_DNS="$(
			printf '%s\n' "$status_raw" |
				awk '
					match($0, /^Link [0-9]+ \(([^)]+)\)/, m) { cur = m[1]; next }
					/^[[:space:]]*Current DNS Server:/ {
						if (cur != "") {
							val = $0
							sub(/^[[:space:]]*Current DNS Server:[[:space:]]*/, "", val)
							if (seen[cur] != 1) {
								seen[cur] = 1
								if (out == "") out = cur " -> " val
								else out = out ", " cur " -> " val
							}
						}
					}
					END { print out }
				'
		)"
	fi

	RESOLVECTL_OK=1
}

fmt_state() {
	local s="$1"
	case "$s" in
	ok) echo "${GRN}OK${RST}" ;;
	localstub) echo "${YLW}LOCAL_STUB${RST}" ;;
	blocked) echo "${YLW}BLOCKED${RST}" ;;
	noanswer) echo "${YLW}NOANSWER${RST}" ;;
	refused) echo "${RED}REFUSED${RST}" ;;
	timeout) echo "${RED}TIMEOUT${RST}" ;;
	nodig) echo "${DIM}NO_DIG${RST}" ;;
	*) echo "${RED}ERR${RST}" ;;
	esac
}

is_blocked_value() {
	local v="${1:-}"
	case "$v" in
	0.0.0.0 | 127.0.0.1 | :: | ::1) return 0 ;;
	*) return 1 ;;
	esac
}

classify_blocking() {
	# Usage: classify_blocking <control_status> <test_status> <test_value>
	local control_status="$1"
	local test_status="$2"
	local test_value="${3:-}"

	if [[ "$control_status" != "ok" ]]; then
		echo "skip"
		return 0
	fi

	if [[ "$test_status" == "ok" ]]; then
		if is_blocked_value "$test_value"; then
			echo "blocked"
		else
			echo "ok"
		fi
		return 0
	fi

	if [[ "$test_status" == "noanswer" ]]; then
		echo "blocked"
		return 0
	fi

	echo "$test_status"
}

show_service_state() {
	local unit="$1"
	if ! have systemctl; then
		echo "${DIM}<systemctl not available>${RST}"
		return 0
	fi

	if systemctl list-unit-files "$unit" >/dev/null 2>&1; then
		if systemctl is-active --quiet "$unit" 2>/dev/null; then
			echo "${GRN}active${RST}"
		else
			local state
			state="$(systemctl show -p ActiveState --value "$unit" 2>/dev/null || echo "unknown")"
			echo "${YLW}${state}${RST}"
		fi
	else
		echo "${DIM}not installed${RST}"
	fi
}

show_dns_status() {
	local verbose="${OSC_DNS_VERBOSE:-0}"
	case "${1:-}" in
	-v | --verbose) verbose=1 ;;
	esac

	echo "=== DNS STATUS ==="
	print_kv "Time" "$(date -Is)"

	local blocky_active=0
	local mullvad_active=0
	local mullvad_state=''
	local mullvad_connected=0
	local resolved_active=0

	if is_active blocky.service; then blocky_active=1; fi
	if is_active mullvad-daemon.service; then mullvad_active=1; fi
	if is_active systemd-resolved.service; then resolved_active=1; fi
	if have mullvad; then
		mullvad_state="$(mullvad status 2>/dev/null | head -n 1 || true)"
		if [[ "$mullvad_state" == Connected* ]]; then
			mullvad_connected=1
		fi
	fi

	local ns_list=()
	while IFS= read -r ns; do
		[[ -n "$ns" ]] || continue
		ns_list+=("$ns")
	done < <(get_nameservers)

	local has_loopback=0
	local ns
	for ns in "${ns_list[@]:-}"; do
		if is_loopback_resolver "$ns"; then
			has_loopback=1
			break
		fi
	done

	local mode='default (isp/custom)'
	if [[ "$blocky_active" -eq 1 && "$mullvad_connected" -eq 1 ]]; then
		mode='conflict (blocky+mullvad)'
	elif [[ "$mullvad_connected" -eq 1 ]]; then
		mode='mullvad vpn'
	elif [[ "$blocky_active" -eq 1 ]]; then
		mode='blocky fallback'
	elif [[ "$has_loopback" -eq 1 && "$resolved_active" -eq 1 ]]; then
		mode='systemd-resolved (local stub)'
	elif [[ "$has_loopback" -eq 1 ]]; then
		mode='local stub'
	fi

	hr
	print_kv "Mode" "$mode"
	print_kv "blocky" "$(show_service_state blocky.service)"
	print_kv "mullvad-daemon" "$(show_service_state mullvad-daemon.service)"
	if [[ -n "$mullvad_state" ]]; then
		print_kv "mullvad" "$mullvad_state"
	fi

	local ns_line
	ns_line="$(join_by ", " "${ns_list[@]:-}")"
	print_kv "resolv.conf" "${ns_line:-<no nameserver>}"

	collect_resolvectl_state
	if [[ "$RESOLVECTL_OK" -eq 1 ]]; then
		[[ -n "$RESOLVECTL_SERVERS" ]] && print_kv "resolvectl dns" "$RESOLVECTL_SERVERS"
		[[ -n "$RESOLVECTL_CURRENT" ]] && print_kv "current dns" "$RESOLVECTL_CURRENT"
		[[ -n "$RESOLVECTL_DNS_LINKS" ]] && print_kv "dns link" "$RESOLVECTL_DNS_LINKS"
		[[ -n "$RESOLVECTL_LINK_DNS" ]] && print_kv "link dns" "$RESOLVECTL_LINK_DNS"
	fi

	if have resolvconf; then
		local sources
		sources="$(resolvconf -i 2>/dev/null | tr '\n' ' ' | sed -E 's/[[:space:]]+/ /g; s/[[:space:]]+$//' || true)"
		[[ -n "$sources" ]] || sources="<none>"
		print_kv "sources" "$sources"
	fi

	if [[ "$has_loopback" -eq 1 && "$blocky_active" -eq 0 && "$resolved_active" -eq 0 ]]; then
		print_kv "warning" "loopback resolvers are configured but no known local DNS service is active"
	fi

	hr
	default_probe
	if [[ "$DEFAULT_STATUS" == "ok" ]]; then
		print_kv "default" "$(fmt_state ok) example.com → ${DEFAULT_VALUE}"
	else
		print_kv "default" "$(fmt_state "$DEFAULT_STATUS") example.com"
	fi

	hr
	echo "${CYN}Resolvers${RST}"
	if [[ ${#ns_list[@]} -eq 0 ]]; then
		echo "${DIM}<no nameserver entries found>${RST}"
	else
		for ns in "${ns_list[@]}"; do
			if is_loopback_resolver "$ns"; then
				local stub_note='upstream unknown'
				if [[ "$RESOLVECTL_OK" -eq 1 && -n "$RESOLVECTL_SERVERS" ]]; then
					stub_note="upstream ${RESOLVECTL_SERVERS}"
				fi
				if [[ "$DEFAULT_STATUS" == "ok" ]]; then
					echo "- ${CYN}${ns}${RST}: $(fmt_state localstub) ${stub_note} | example $(fmt_state ok) ${DEFAULT_VALUE}"
				else
					echo "- ${CYN}${ns}${RST}: $(fmt_state localstub) ${stub_note}"
				fi
				continue
			fi

			dig_probe "$ns" example.com A
			local c_status="$DIG_STATUS"
			local c_value="$DIG_VALUE"
			local c_raw="$DIG_RAW"

			if [[ "$c_status" != "ok" ]]; then
				echo "- ${CYN}${ns}${RST}: $(fmt_state "$c_status")"
				if [[ "$verbose" -eq 1 && -n "$c_raw" ]]; then
					echo "  ${DIM}${c_raw}${RST}"
				fi
				continue
			fi

			dig_probe "$ns" ad.doubleclick.net A
			local ad_status
			ad_status="$(classify_blocking "$c_status" "$DIG_STATUS" "$DIG_VALUE")"

			dig_probe "$ns" www.youtube.com A
			local yt_status
			yt_status="$(classify_blocking "$c_status" "$DIG_STATUS" "$DIG_VALUE")"

			echo "- ${CYN}${ns}${RST}: example $(fmt_state ok) ${c_value} | ads $(fmt_state "$ad_status") | youtube $(fmt_state "$yt_status")"
		done
	fi

	if [[ "$verbose" -eq 1 ]]; then
		hr
		echo "${CYN}/etc/resolv.conf${RST}"
		if [[ -r /etc/resolv.conf ]]; then
			sed -n '1,60p' /etc/resolv.conf
		else
			echo "${DIM}<not readable>${RST}"
		fi

		if [[ -n "$RESOLVECTL_DNS_RAW" ]]; then
			hr
			echo "${CYN}resolvectl dns${RST}"
			printf '%s\n' "$RESOLVECTL_DNS_RAW"
		elif [[ -n "$RESOLVECTL_ERROR" ]]; then
			hr
			echo "${CYN}resolvectl${RST}"
			echo "${DIM}${RESOLVECTL_ERROR}${RST}"
		fi
	fi
}

usage() {
	cat <<EOF
Usage:
  ${SCRIPT_NAME} status [--verbose]

Commands:
  status   Show a short DNS summary + quick tests

Flags:
  -v, --verbose   Include raw dig errors and /etc/resolv.conf
EOF
}

main() {
	case "${1:-status}" in
	-v | --verbose)
		show_dns_status --verbose
		;;
	status)
		shift || true
		show_dns_status "$@"
		;;
	-h | --help | help) usage ;;
	*)
		echo "${RED}Unknown command:${RST} ${1:-}" >&2
		usage >&2
		exit 2
		;;
	esac
}

main "$@"
