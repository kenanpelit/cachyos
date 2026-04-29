#!/usr/bin/env bash
# ==============================================================================
# Script: mango-arrange
# Description: Profile-aware tag/window arrangement for MangoWM.
# Usage: mango-arrange [profile|go]
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMMON_HELPER="${SCRIPT_DIR}/mango-session-common.sh"
[[ -r "${COMMON_HELPER}" ]] || COMMON_HELPER="${SCRIPT_DIR}/mango-session-common"
# shellcheck source=mango-session-common.sh
source "${COMMON_HELPER}"

PROFILE_FILE="${MANGO_PROFILE_FILE:-}"
WORKSPACE_RULES_FILE="${MANGO_WORKSPACE_RULES_FILE:-}"
LOG_TAG="mango-arrange"

log() { printf '[%s] %s\n' "${LOG_TAG}" "$*" >&2; }
warn() { printf '[%s] WARN: %s\n' "${LOG_TAG}" "$*" >&2; }

export PATH="$HOME/.local/bin:$HOME/bin:/usr/local/bin:/usr/bin:/bin:${PATH:-}"

locate_profile_file() {
	local candidate=""
	local config_home="${XDG_CONFIG_HOME:-$HOME/.config}"

	if [[ -n "${PROFILE_FILE}" && -r "${PROFILE_FILE}" ]]; then
		printf '%s\n' "${PROFILE_FILE}"
		return 0
	fi

	for candidate in \
		"${config_home}/mango/generated/profile.conf" \
		"${config_home}/mango/runtime/profile.conf" \
		"/etc/xdg/mango/generated/profile.conf" \
		"/etc/xdg/mango/runtime/profile.conf"; do
		if [[ -r "${candidate}" ]]; then
			printf '%s\n' "${candidate}"
			return 0
		fi
	done

	return 1
}

locate_workspace_rules_file() {
	local candidate=""
	local config_home="${XDG_CONFIG_HOME:-$HOME/.config}"

	if [[ -n "${WORKSPACE_RULES_FILE}" && -r "${WORKSPACE_RULES_FILE}" ]]; then
		printf '%s\n' "${WORKSPACE_RULES_FILE}"
		return 0
	fi

	for candidate in \
		"${config_home}/mango/generated/workspace-rules.conf" \
		"${config_home}/mango/runtime/workspace-rules.conf" \
		"/etc/xdg/mango/generated/workspace-rules.conf" \
		"/etc/xdg/mango/runtime/workspace-rules.conf"; do
		if [[ -r "${candidate}" ]]; then
			printf '%s\n' "${candidate}"
			return 0
		fi
	done

	return 1
}

usage() {
	cat <<'EOF'
Usage:
  mango-arrange [profile]
  mango-arrange go [--dry-run] [--verbose]

profile:
  Reconcile monitor/tag ownership from generated/profile.conf.

go:
  Move open windows back to the tag/monitor selected by generated
  workspace-rules.conf, then finish focused on Kenp.
EOF
}

setup_session() {
	mango_ensure_runtime_dir
	mango_ensure_session_identity
	mango_detect_wayland_display || true

	if ! command -v mmsg >/dev/null 2>&1; then
		warn "mmsg not found; skipping arrangement"
		return 1
	fi

	PROFILE_FILE="$(locate_profile_file || true)"

	if [[ -z "${PROFILE_FILE}" ]]; then
		warn "profile file not found"
		return 1
	fi

	if ! mmsg -g -o >/dev/null 2>&1; then
		warn "cannot query Mango outputs; skipping arrangement"
		return 1
	fi

	return 0
}

declare -a TARGET_PAIRS=()
declare -a RULE_TAGS=()
declare -a RULE_MONITORS=()
declare -a RULE_APP_PATTERNS=()
declare -a RULE_TITLE_PATTERNS=()
declare -A VIEW_PRIMARY=()
declare -A VIEW_ADDITIONAL=()
SELECTED_MONITOR=""

load_profile_pairs() {
	mapfile -t target_pairs < <(
		awk -F',' '
      /^tagrule=/ {
        tag=""
        monitor=""
        for (i = 1; i <= NF; i++) {
          if ($i ~ /^tagrule=id:/) {
            tag = $i
            sub(/^tagrule=id:/, "", tag)
          } else if ($i ~ /^monitor_name:/) {
            monitor = $i
            sub(/^monitor_name:/, "", monitor)
          }
        }
        if (tag != "" && monitor != "") {
          print monitor "\t" tag
        }
      }
	    ' "${PROFILE_FILE}" | awk -F'\t' '!seen[$1]++'
	)
	TARGET_PAIRS=("${target_pairs[@]}")

	if ((${#TARGET_PAIRS[@]} == 0)); then
		warn "no tag mappings found in ${PROFILE_FILE}"
		return 1
	fi

	return 0
}

monitor_for_tag() {
	local wanted_tag="$1"
	local pair monitor tag

	for pair in "${TARGET_PAIRS[@]}"; do
		monitor="${pair%%$'\t'*}"
		tag="${pair#*$'\t'}"
		if [[ "${tag}" == "${wanted_tag}" ]]; then
			printf '%s\n' "${monitor}"
			return 0
		fi
	done

	return 1
}

arrange_profile() {
	load_profile_pairs || return 0

	local first_monitor=""
	local first_tag=""
	local pair monitor tag

	for pair in "${TARGET_PAIRS[@]}"; do
		monitor="${pair%%$'\t'*}"
		tag="${pair#*$'\t'}"
		[[ -n "${monitor}" && -n "${tag}" ]] || continue
		if [[ -z "${first_monitor}" ]]; then
			first_monitor="${monitor}"
			first_tag="${tag}"
		fi
		mmsg -s -o "${monitor}" -t "${tag}" >/dev/null 2>&1 || true
	done

	if [[ -n "${first_monitor}" && -n "${first_tag}" ]]; then
		mmsg -d "focusmon,${first_monitor}" >/dev/null 2>&1 || true
		mmsg -s -o "${first_monitor}" -t "${first_tag}" >/dev/null 2>&1 || true
		log "focused ${first_monitor} on tag ${first_tag}"
	fi
}

selected_monitor() {
	mmsg -g -o 2>/dev/null | awk '$2 == "selmon" && $3 == "1" { print $1; exit }'
}

snapshot_views() {
	local mon active_tag

	VIEW_PRIMARY=()
	VIEW_ADDITIONAL=()
	SELECTED_MONITOR="$(selected_monitor 2>/dev/null || true)"

	while read -r mon active_tag; do
		[[ -n "${mon}" && -n "${active_tag}" ]] || continue
		if [[ -z "${VIEW_PRIMARY[$mon]+x}" ]]; then
			VIEW_PRIMARY[$mon]="${active_tag}"
		else
			VIEW_ADDITIONAL[$mon]="${VIEW_ADDITIONAL[$mon]:-} ${active_tag}"
		fi
	done < <(
		mmsg -g -t 2>/dev/null | awk '$2 == "tag" && (($4 + 0) % 2) == 1 { print $1, $3 }'
	)
}

restore_views() {
	local mon active_tag

	for mon in "${!VIEW_PRIMARY[@]}"; do
		mmsg -s -o "${mon}" -t "${VIEW_PRIMARY[$mon]}" >/dev/null 2>&1 || true
		for active_tag in ${VIEW_ADDITIONAL[$mon]:-}; do
			mmsg -s -o "${mon}" -t "${active_tag}+" >/dev/null 2>&1 || true
		done
	done

	if [[ -n "${SELECTED_MONITOR:-}" ]]; then
		mmsg -d "focusmon,${SELECTED_MONITOR}" >/dev/null 2>&1 || true
	fi
}

load_route_rules() {
	local line body part tag monitor app_regex title_regex

	WORKSPACE_RULES_FILE="$(locate_workspace_rules_file || true)"
	if [[ -z "${WORKSPACE_RULES_FILE}" ]]; then
		warn "workspace rules file not found"
		return 1
	fi

	RULE_TAGS=()
	RULE_MONITORS=()
	RULE_APP_PATTERNS=()
	RULE_TITLE_PATTERNS=()

	while IFS= read -r line; do
		[[ "${line}" == windowrule=* ]] || continue
		body="${line#windowrule=}"
		tag=""
		monitor=""
		app_regex=""
		title_regex=""

		IFS=',' read -r -a parts <<<"${body}"
		for part in "${parts[@]}"; do
			case "${part}" in
				tags:*) tag="${part#tags:}" ;;
				monitor:*) monitor="${part#monitor:}" ;;
				appid:*) app_regex="${part#appid:}" ;;
				title:*) title_regex="${part#title:}" ;;
			esac
		done

		[[ -n "${tag}" ]] || continue
		[[ -n "${monitor}" ]] || monitor="$(monitor_for_tag "${tag}" 2>/dev/null || true)"
		RULE_TAGS+=("${tag}")
		RULE_MONITORS+=("${monitor}")
		RULE_APP_PATTERNS+=("${app_regex}")
		RULE_TITLE_PATTERNS+=("${title_regex}")
	done <"${WORKSPACE_RULES_FILE}"

	((${#RULE_TAGS[@]} > 0))
}

focused_appid_on_monitor() {
	local mon="$1"
	mmsg -g -c 2>/dev/null | awk -v mon="${mon}" '
    $1 == mon && $2 == "appid" {
      sub($1 FS $2 FS, "")
      print
      exit
    }
  '
}

focused_title_on_monitor() {
	local mon="$1"
	mmsg -g -c 2>/dev/null | awk -v mon="${mon}" '
    $1 == mon && $2 == "title" {
      sub($1 FS $2 FS, "")
      print
      exit
    }
  '
}

clients_in_tag() {
	local mon="$1"
	local tag="$2"

	mmsg -g -t 2>/dev/null | awk -v mon="${mon}" -v tag="${tag}" '
    $1 == mon && $2 == "tag" && $3 == tag {
      print $5
      exit
    }
  '
}

focus_source_tag() {
	local mon="$1"
	local tag="$2"

	mmsg -d "focusmon,${mon}" >/dev/null 2>&1 || true
	mmsg -s -o "${mon}" -t "${tag}" >/dev/null 2>&1 || true
}

advance_source_focus() {
	local mon="$1"
	local tag="$2"

	focus_source_tag "${mon}" "${tag}"
	mmsg -d "focusstack,next" >/dev/null 2>&1 || true
	sleep 0.03
}

target_for_client() {
	local app_id="${1:-}"
	local title="${2:-}"
	local i app_pattern title_pattern

	for i in "${!RULE_TAGS[@]}"; do
		app_pattern="${RULE_APP_PATTERNS[$i]:-}"
		title_pattern="${RULE_TITLE_PATTERNS[$i]:-}"

		if [[ -n "${app_pattern}" && ! "${app_id}" =~ ${app_pattern} ]]; then
			continue
		fi
		if [[ -n "${title_pattern}" && ! "${title}" =~ ${title_pattern} ]]; then
			continue
		fi
		if [[ -z "${app_pattern}" && -z "${title_pattern}" ]]; then
			continue
		fi

		printf '%s\t%s\n' "${RULE_TAGS[$i]}" "${RULE_MONITORS[$i]}"
		return 0
	done

	return 1
}

focus_kenp() {
	local home_monitor=""
	local here_bin="${SCRIPT_DIR}/mango-here.sh"

	home_monitor="$(monitor_for_tag "1" 2>/dev/null || true)"
	if [[ -n "${home_monitor}" ]]; then
		mmsg -d "focusmon,${home_monitor}" >/dev/null 2>&1 || true
		mmsg -s -o "${home_monitor}" -t "1" >/dev/null 2>&1 || true
	fi

	[[ -x "${here_bin}" ]] || here_bin="mango-here"
	if command -v "${here_bin}" >/dev/null 2>&1 || [[ -x "${here_bin}" ]]; then
		"${here_bin}" 1 "${home_monitor:-}" Kenp >/dev/null 2>&1 || true
	fi
}

go_arrange() {
	local dry_run=0
	local verbose=0
	local arg row mon tag count i appid title target target_tag target_monitor moved_this_pass
	local planned=0
	local moved=0
	local failed=0

	while (($#)); do
		arg="$1"
		case "${arg}" in
			--dry-run)
				dry_run=1
				shift
				;;
			--verbose)
				verbose=1
				shift
				;;
			-h|--help)
				usage
				return 0
				;;
			*)
				usage >&2
				return 2
				;;
		esac
	done

	load_profile_pairs || return 0
	load_route_rules || return 0
	snapshot_views

	mapfile -t occupied_tags < <(
		mmsg -g -t 2>/dev/null | awk '$2 == "tag" && $5 > 0 { print $1 "\t" $3 "\t" $5 }'
	)

	for row in "${occupied_tags[@]}"; do
		IFS=$'\t' read -r mon tag count <<<"${row}"
		[[ -n "${mon}" && -n "${tag}" && "${count}" =~ ^[0-9]+$ ]] || continue
		((count > 0)) || continue

		while :; do
			count="$(clients_in_tag "${mon}" "${tag}" 2>/dev/null || true)"
			[[ "${count}" =~ ^[0-9]+$ ]] || count=0
			((count > 0)) || break

			focus_source_tag "${mon}" "${tag}"
			sleep 0.03
			moved_this_pass=0

			for ((i = 0; i < count; i++)); do
				appid="$(focused_appid_on_monitor "${mon}" 2>/dev/null || true)"
				title="$(focused_title_on_monitor "${mon}" 2>/dev/null || true)"
				if [[ -z "${appid}" && -z "${title}" ]]; then
					break
				fi

				target="$(target_for_client "${appid}" "${title}" 2>/dev/null || true)"
				if [[ -z "${target}" ]]; then
					advance_source_focus "${mon}" "${tag}"
					continue
				fi

				IFS=$'\t' read -r target_tag target_monitor <<<"${target}"
				[[ -n "${target_monitor}" ]] || target_monitor="$(monitor_for_tag "${target_tag}" 2>/dev/null || true)"
				if [[ -z "${target_monitor}" ]]; then
					failed=$((failed + 1))
					warn "cannot resolve target monitor for ${appid:-<no-appid>} -> tag ${target_tag}"
					advance_source_focus "${mon}" "${tag}"
					continue
				fi

				if [[ "${target_tag}" == "${tag}" && "${target_monitor}" == "${mon}" ]]; then
					((verbose == 1)) && log "already placed: ${appid:-<no-appid>} -> tag ${target_tag} on ${target_monitor}"
					advance_source_focus "${mon}" "${tag}"
					continue
				fi

				planned=$((planned + 1))
				if ((dry_run == 1)); then
					log "dry-run: ${appid:-<no-appid>} -> tag ${target_tag} on ${target_monitor}"
					advance_source_focus "${mon}" "${tag}"
					continue
				fi

				if mmsg -d "tagcrossmon,${target_tag},${target_monitor}" >/dev/null 2>&1; then
					moved=$((moved + 1))
					moved_this_pass=1
					((verbose == 1)) && log "moved: ${appid:-<no-appid>} -> tag ${target_tag} on ${target_monitor}"
					focus_source_tag "${mon}" "${tag}"
					sleep 0.04
					break
				else
					failed=$((failed + 1))
					warn "failed to move ${appid:-<no-appid>} -> tag ${target_tag} on ${target_monitor}"
					advance_source_focus "${mon}" "${tag}"
				fi
			done

			((dry_run == 1)) && break
			((moved_this_pass == 1)) || break
		done
	done

	if ((dry_run == 1)); then
		restore_views
		log "dry-run complete: ${planned} window(s) would move"
	else
		arrange_profile
		focus_kenp
		log "go complete: moved ${moved}/${planned}, failed ${failed}"
	fi

	((failed == 0))
}

main() {
	local command="${1:-profile}"
	[[ "${command}" != "profile" ]] || shift || true

	case "${command}" in
		-h|--help|help)
			usage
			exit 0
			;;
	esac

	setup_session || exit 0

	case "${command}" in
		profile)
			(($# == 0)) || {
				usage >&2
				exit 2
			}
			arrange_profile
			;;
		go)
			shift || true
			go_arrange "$@"
			;;
		*)
			usage >&2
			exit 2
			;;
	esac
}

main "$@"
