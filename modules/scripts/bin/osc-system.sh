#!/usr/bin/env bash
# ==============================================================================
# OSC-SYSTEM: Unified Power Management & Monitoring Utility
# ==============================================================================
# Version: 18.0
# Author: Kenan
# License: MIT
#
# Description:
# ------------
# Comprehensive system power management, monitoring, and analysis tool.
# Integrates system status, thermal monitoring, CPU analysis, and power tracking.
#
# Usage:
#   osc-system <command> [options]
#
# Commands:
#   status              Show comprehensive system status
#   thermal             Monitor thermal, power, and fan metrics
#   turbostat-quick     Quick CPU frequency analysis (requires root)
#   turbostat-stress    Performance testing under load (requires root)
#   turbostat-analyze   Parse and analyze turbostat output (requires root)
#   power-check         Measure instantaneous power consumption
#   power-monitor       Real-time power monitoring dashboard
#   profile-refresh     Restart all power management services (requires root)
#   help                Show this help message
#
# For command-specific help:
#   osc-system <command> --help
#
# ==============================================================================

set -euo pipefail

VERSION="18.0"
SCRIPT_NAME=$(basename "$0")
SCRIPT_ABS_PATH="$(readlink -f "${BASH_SOURCE[0]}" 2>/dev/null || true)"
if [[ -z "$SCRIPT_ABS_PATH" ]]; then
	SCRIPT_ABS_PATH="$(command -v "$SCRIPT_NAME" 2>/dev/null || true)"
fi
SUDO_SCRIPT_CMD="${SCRIPT_ABS_PATH:-$SCRIPT_NAME}"
LOG_BASE_DIR="${HOME}/.logs"
THERMAL_LOG_DIR="${LOG_BASE_DIR}/thermal"

# ==============================================================================
# Color Definitions
# ==============================================================================
if [[ -t 1 ]]; then
	BOLD=$'\e[1m'
	DIM=$'\e[2m'
	RED=$'\e[31m'
	GRN=$'\e[32m'
	YLW=$'\e[33m'
	BLU=$'\e[34m'
	MAG=$'\e[35m'
	CYN=$'\e[36m'
	RST=$'\e[0m'
else
	BOLD="" DIM="" RED="" GRN="" YLW="" BLU="" MAG="" CYN="" RST=""
fi

# ==============================================================================
# Helper Functions
# ==============================================================================
have() { command -v "$1" >/dev/null 2>&1; }
read_file() { [[ -r "$1" ]] && cat "$1" || return 1; }
ensure_log_dir() {
	local dir="$1"
	[[ ! -d "$dir" ]] && mkdir -p "$dir" && echo -e "${GRN}Created log directory: ${dir}${RST}"
}
run_state_get() { read_file "/run/osc-power/$1" 2>/dev/null || return 1; }

# ==============================================================================
# Main Help
# ==============================================================================
show_help() {
	cat <<EOF
${BOLD}${CYN}OSC-SYSTEM v${VERSION}${RST} - Unified Power Management & Monitoring Utility

${BOLD}Usage:${RST} ${SCRIPT_NAME} <command> [options]

${BOLD}Commands:${RST}
  ${CYN}status${RST}              Show comprehensive system status
  ${CYN}thermal${RST}             Monitor thermal, power, and fan metrics
  ${CYN}turbostat-quick${RST}     Quick CPU frequency analysis (requires root)
  ${CYN}turbostat-stress${RST}    Performance testing under load (requires root)
  ${CYN}turbostat-analyze${RST}   Parse and analyze turbostat output (requires root)
  ${CYN}power-check${RST}         Measure instantaneous power consumption
  ${CYN}power-monitor${RST}       Real-time power monitoring dashboard
  ${CYN}profile-refresh${RST}     Restart all power management services (requires root)
  ${CYN}help${RST}, -h, --help    Show this help message

${BOLD}Examples:${RST}
  ${SCRIPT_NAME} status
  ${SCRIPT_NAME} status --json
  ${SCRIPT_NAME} thermal -d 300 -p
  sudo ${SUDO_SCRIPT_CMD} turbostat-quick
  ${SCRIPT_NAME} power-monitor
  sudo ${SUDO_SCRIPT_CMD} profile-refresh

${BOLD}For command-specific help:${RST}
  ${SCRIPT_NAME} <command> --help

${BOLD}Features:${RST}
  ✓ Real-time power consumption tracking
  ✓ Thermal monitoring with CSV logging
  ✓ CPU frequency analysis (turbostat)
  ✓ RAPL power limit awareness
  ✓ Battery health & thresholds
  ✓ Service status tracking
  ✓ JSON output for automation

EOF
}

# ==============================================================================
# COMMAND: status
# ==============================================================================
cmd_status() {
	json_out=false
	brief_out=false
	sample_power=false

	while [[ $# -gt 0 ]]; do
		case "$1" in
		--json) json_out=true ;;
		--brief) brief_out=true ;;
		--sample-power) sample_power=true ;;
		-h | --help)
			cat <<EOF
${BOLD}Status Command${RST} - Show comprehensive system status

${BOLD}Usage:${RST} ${SCRIPT_NAME} status [OPTIONS]

${BOLD}Options:${RST}
  --json           Machine-readable JSON output (requires jq)
  --brief          Brief human-readable output
  --sample-power   Measure actual power consumption (~2s sample)
  -h, --help       Show this help

${BOLD}Features:${RST}
  ✅ CPU Type (Intel/AMD detection)
  ✅ Power Source (AC/Battery)
  ✅ P-State Mode & Min/Max Performance
  ✅ Turbo + HWP Dynamic Boost status
  ✅ EPP (Energy Performance Preference)
  ✅ Platform Profile (balanced/performance/low-power)
  ✅ CPU Frequencies snapshot
  ✅ Temperature (sensors)
  ✅ RAPL Power Limits (PL1/PL2/PL4)
  ✅ Battery Status & Charge Thresholds
  ✅ Service Health Status
  ✅ MMIO Status (intel_rapl_mmio)

${BOLD}Examples:${RST}
  ${SCRIPT_NAME} status
  ${SCRIPT_NAME} status --json | jq '.epp_any'
  ${SCRIPT_NAME} status --sample-power
  watch -n 2 ${SCRIPT_NAME} status --brief

EOF
			return 0
			;;
		*)
			echo "${RED}Unknown option: $1${RST}" >&2
			return 2
			;;
		esac
		shift
	done

	# CPU type detection
	CPU_TYPE="unknown"
	grep -q "Intel" /proc/cpuinfo 2>/dev/null && CPU_TYPE="intel"
	grep -q "AMD" /proc/cpuinfo 2>/dev/null && CPU_TYPE="amd"

	# Power source detection
	ON_AC=0
	for PS in /sys/class/power_supply/AC*/online /sys/class/power_supply/ADP*/online; do
		[[ -f "$PS" ]] && {
			ON_AC="$(cat "$PS")"
			break
		}
	done
	POWER_SRC=$([[ "${ON_AC}" = "1" ]] && echo "AC" || echo "Battery")

	# Load average (helps interpret "400MHz" reports)
	LOAD1="0.00"
	if [[ -r /proc/loadavg ]]; then
		LOAD1="$(awk '{print $1}' /proc/loadavg 2>/dev/null || echo "0.00")"
	fi

	# P-State / governor / turbo / HWP boost
	# NOTE:
	# On Intel `intel_pstate=active` systems, `/sys/.../cpu0/.../scaling_governor`
	# may misleadingly stay at "powersave" even when policies are configured for
	# performance. Prefer policy-level knobs for reporting.
	GOVERNOR_CPU0="$(read_file /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2>/dev/null || echo "unknown")"
	PSTATE="$(read_file /sys/devices/system/cpu/intel_pstate/status 2>/dev/null || echo "unknown")"

	NO_TURBO="$(read_file /sys/devices/system/cpu/intel_pstate/no_turbo 2>/dev/null || echo "1")"
	TURBO_ENABLED=$([[ "${NO_TURBO}" = "0" ]] && echo true || echo false)

	HWP_BOOST="$(read_file /sys/devices/system/cpu/intel_pstate/hwp_dynamic_boost 2>/dev/null || echo "0")"
	HWP_BOOST_BOOL=$([[ "${HWP_BOOST}" = "1" ]] && echo true || echo false)

	MIN_PERF="$(read_file /sys/devices/system/cpu/intel_pstate/min_perf_pct 2>/dev/null || echo "0")"
	MAX_PERF="$(read_file /sys/devices/system/cpu/intel_pstate/max_perf_pct 2>/dev/null || echo "0")"

	# Governor (policy-level distribution)
	GOVERNOR_ANY="unknown"
	declare -A GOV_MAP || true
	GOV_COUNT=0
	for pol in /sys/devices/system/cpu/cpufreq/policy*; do
		[[ -r "$pol/scaling_governor" ]] || continue
		gov="$(cat "$pol/scaling_governor")"
		GOVERNOR_ANY="$gov"
		GOV_MAP["$gov"]=$((${GOV_MAP["$gov"]:-0} + 1))
		GOV_COUNT=$((GOV_COUNT + 1))
	done
	# Fallback for kernels without policy governors.
	[[ "$GOVERNOR_ANY" == "unknown" ]] && GOVERNOR_ANY="$GOVERNOR_CPU0"

	# EPP (Energy Performance Preference)
	EPP_ANY="unknown"
	declare -A EPP_MAP || true
	EPP_COUNT=0
	for pol in /sys/devices/system/cpu/cpufreq/policy*; do
		[[ -r "$pol/energy_performance_preference" ]] || continue
		epp="$(cat "$pol/energy_performance_preference")"
		EPP_ANY="$epp"
		EPP_MAP["$epp"]=$((${EPP_MAP["$epp"]:-0} + 1))
		EPP_COUNT=$((EPP_COUNT + 1))
	done

	# CPU Frequency snapshot
	FREQ_SUM=0 FREQ_CNT=0
	for f in /sys/devices/system/cpu/cpu[0-9]*/cpufreq/scaling_cur_freq; do
		[[ -f "$f" ]] || continue
		val="$(cat "$f")"
		FREQ_SUM=$((FREQ_SUM + val))
		FREQ_CNT=$((FREQ_CNT + 1))
	done
	FREQ_AVG_MHZ=0
	[[ $FREQ_CNT -gt 0 ]] && FREQ_AVG_MHZ=$((FREQ_SUM / FREQ_CNT / 1000))

	# Some kernels/drivers (notably Intel HWP/intel_pstate=active) may report
	# stale/placeholder values via scaling_cur_freq. As an additional "best-effort"
	# signal, compute average MHz from /proc/cpuinfo (what users commonly expect).
	CPUINFO_FREQ_AVG_MHZ="0"
	declare -A CPUINFO_MHZ_BY_CPU || true
	if [[ -r /proc/cpuinfo ]]; then
		# Build a per-CPU MHz map from /proc/cpuinfo (more intuitive than sysfs on HWP).
		cur_cpu=""
		while IFS= read -r line; do
			if [[ "$line" =~ ^processor[[:space:]]*:[[:space:]]*([0-9]+)$ ]]; then
				cur_cpu="${BASH_REMATCH[1]}"
				continue
			fi
			if [[ -n "$cur_cpu" && "$line" =~ ^cpu[[:space:]]MHz[[:space:]]*:[[:space:]]*([0-9]+(\.[0-9]+)?)$ ]]; then
				CPUINFO_MHZ_BY_CPU["$cur_cpu"]="${BASH_REMATCH[1]}"
				continue
			fi
		done </proc/cpuinfo

		CPUINFO_FREQ_AVG_MHZ="$(
			awk -F: '
				/^cpu MHz/ {gsub(/^[[:space:]]+/, "", $2); sum+=$2; n++}
				END {if(n>0) printf("%d\n", sum/n); else print 0}
			' /proc/cpuinfo 2>/dev/null || echo 0
		)"
	fi

	# Temperature
	TEMP_C="0"
	if have sensors; then
		TEMP_C="$(sensors 2>/dev/null | grep -E 'Package id 0|Tctl' |
			awk '{match($0, /[+]?([0-9]+\.[0-9]+)/, a); if(a[1]!=""){print a[1]; exit}}' || echo "0")"
	fi
	[[ -z "$TEMP_C" ]] && TEMP_C="0"

	# RAPL Power Limits
	PL1_W=0 PL2_W=0 PL4_W=0 BASE_PL2_W=0
	PL1_MAX_W=0 PL2_MAX_W=0
	if [[ -d /sys/class/powercap/intel-rapl:0 ]]; then
		PL1_W=$(($(read_file /sys/class/powercap/intel-rapl:0/constraint_0_power_limit_uw 2>/dev/null || echo 0) / 1000000))
		PL2_W=$(($(read_file /sys/class/powercap/intel-rapl:0/constraint_1_power_limit_uw 2>/dev/null || echo 0) / 1000000))
		PL4_W=$(($(read_file /sys/class/powercap/intel-rapl:0/constraint_2_power_limit_uw 2>/dev/null || echo 0) / 1000000))
		PL1_MAX_W=$(($(read_file /sys/class/powercap/intel-rapl:0/constraint_0_max_power_uw 2>/dev/null || echo 0) / 1000000))
		PL2_MAX_W=$(($(read_file /sys/class/powercap/intel-rapl:0/constraint_1_max_power_uw 2>/dev/null || echo 0) / 1000000))
		[[ -r /var/run/rapl-base-pl2 ]] && BASE_PL2_W=$(cat /var/run/rapl-base-pl2)
	fi

	# MMIO Status
	MMIO_STATUS="disabled"
	MMIO_LOADED=false
	if lsmod 2>/dev/null | grep -q "^intel_rapl_mmio"; then
		MMIO_STATUS="active"
		MMIO_LOADED=true
	fi

	# Platform Profile
	PLATFORM_PROFILE_SYSFS="$(read_file /sys/firmware/acpi/platform_profile 2>/dev/null || echo "unknown")"
	PLATFORM_PROFILE_DESIRED="unknown"
	if run_state_get "desired/platform_profile" >/dev/null 2>&1; then
		PLATFORM_PROFILE_DESIRED="$(run_state_get "desired/platform_profile" 2>/dev/null || echo "unknown")"
	elif have journalctl; then
		last_pp="$(journalctl -b -t power-mgmt-platform-profile -o cat -n 200 2>/dev/null \
			| grep -E 'Platform profile (set to:|already:)' \
			| tail -n 1 \
			|| true)"
		if [[ "$last_pp" =~ Platform[[:space:]]profile[[:space:]](set[[:space:]]to|already:)[[:space:]]([A-Za-z0-9_-]+) ]]; then
			PLATFORM_PROFILE_DESIRED="${BASH_REMATCH[2]}"
		fi
	fi

	# Desired targets (best-effort, from power-mgmt logs)
	GOVERNOR_DESIRED="unknown"
	EPP_DESIRED="unknown"
	if run_state_get "desired/governor" >/dev/null 2>&1; then
		GOVERNOR_DESIRED="$(run_state_get "desired/governor" 2>/dev/null || echo "unknown")"
	elif have journalctl; then
		last_gov="$(journalctl -b -t power-mgmt-cpu-governor -o cat -n 400 2>/dev/null \
			| grep -E 'Governor set to ' \
			| tail -n 1 \
			|| true)"
		if [[ "$last_gov" =~ Governor[[:space:]]set[[:space:]]to[[:space:]]([A-Za-z0-9_-]+) ]]; then
			GOVERNOR_DESIRED="${BASH_REMATCH[1]}"
		fi
	fi

	if run_state_get "desired/epp" >/dev/null 2>&1; then
		EPP_DESIRED="$(run_state_get "desired/epp" 2>/dev/null || echo "unknown")"
	elif have journalctl; then
		last_epp="$(journalctl -b -t power-mgmt-cpu-epp -o cat -n 400 2>/dev/null \
			| grep -E 'Setting EPP to:' \
			| tail -n 1 \
			|| true)"
		if [[ "$last_epp" =~ Setting[[:space:]]EPP[[:space:]]to:[[:space:]]([A-Za-z0-9_-]+) ]]; then
			EPP_DESIRED="${BASH_REMATCH[1]}"
		fi
	fi

	# Battery Status
	BAT_JSON="[]"
	BAT_LINES=()
	for bat in /sys/class/power_supply/BAT*; do
		[[ -d "$bat" ]] || continue
		name="${bat##*/}"
		cap="$(read_file "$bat/capacity" 2>/dev/null || echo "N/A")"
		stat="$(read_file "$bat/status" 2>/dev/null || echo "N/A")"
		start="$(read_file "$bat/charge_control_start_threshold" 2>/dev/null || echo "N/A")"
		stop="$(read_file "$bat/charge_control_end_threshold" 2>/dev/null || echo "N/A")"
		BAT_LINES+=("  ${name}: ${cap}% (${stat}) [thresholds: ${start}-${stop}%]")
		if have jq; then
			BAT_JSON="$(jq -cn --arg name "$name" --arg cap "$cap" --arg stat "$stat" \
				--arg start "$start" --arg stop "$stop" --argjson cur "$BAT_JSON" \
				'$cur + [{name:$name, capacity:$cap, status:$stat, start:$start, stop:$stop}]')"
		fi
	done

	# Power backend / auto-profile automation status
	PPD_LOAD="$(systemctl show -p LoadState --value power-profiles-daemon.service 2>/dev/null || true)"
	PPD_STATE="$(systemctl show -p ActiveState --value power-profiles-daemon.service 2>/dev/null || true)"
	PPD_SUBSTATE="$(systemctl show -p SubState --value power-profiles-daemon.service 2>/dev/null || true)"
	PPD_RESULT="$(systemctl show -p Result --value power-profiles-daemon.service 2>/dev/null || true)"
	PPD_CURRENT="$(powerprofilesctl get 2>/dev/null || true)"
	[[ -z "$PPD_CURRENT" ]] && PPD_CURRENT="unknown"

	USER_SYSTEMD_AVAILABLE=false
	PPP_TIMER_LOAD="" PPP_TIMER_STATE="" PPP_TIMER_SUBSTATE="" PPP_TIMER_RESULT=""
	PPP_SERVICE_LOAD="" PPP_SERVICE_STATE="" PPP_SERVICE_SUBSTATE="" PPP_SERVICE_RESULT=""
	if systemctl --user show-environment >/dev/null 2>&1; then
		USER_SYSTEMD_AVAILABLE=true
		PPP_TIMER_LOAD="$(systemctl --user show -p LoadState --value ppp-auto-profile.timer 2>/dev/null || true)"
		PPP_TIMER_STATE="$(systemctl --user show -p ActiveState --value ppp-auto-profile.timer 2>/dev/null || true)"
		PPP_TIMER_SUBSTATE="$(systemctl --user show -p SubState --value ppp-auto-profile.timer 2>/dev/null || true)"
		PPP_TIMER_RESULT="$(systemctl --user show -p Result --value ppp-auto-profile.timer 2>/dev/null || true)"

		PPP_SERVICE_LOAD="$(systemctl --user show -p LoadState --value ppp-auto-profile.service 2>/dev/null || true)"
		PPP_SERVICE_STATE="$(systemctl --user show -p ActiveState --value ppp-auto-profile.service 2>/dev/null || true)"
		PPP_SERVICE_SUBSTATE="$(systemctl --user show -p SubState --value ppp-auto-profile.service 2>/dev/null || true)"
		PPP_SERVICE_RESULT="$(systemctl --user show -p Result --value ppp-auto-profile.service 2>/dev/null || true)"
	fi

	PPP_LOCK_FILE="${HOME}/.local/state/ppd-auto-profile/lock"
	PPP_LOCKED=false
	PPP_LOCK_PROFILE=""
	if [[ -f "$PPP_LOCK_FILE" ]]; then
		PPP_LOCKED=true
		PPP_LOCK_PROFILE="$(awk -F= '/^profile=/{print $2; exit}' "$PPP_LOCK_FILE" 2>/dev/null || true)"
	fi

	# Sample Power (if requested)
	PKG_W_NOW=""
	if $sample_power && [[ -r /sys/class/powercap/intel-rapl:0/energy_uj ]]; then
		E0="$(cat /sys/class/powercap/intel-rapl:0/energy_uj)"
		sleep 2
		E1="$(cat /sys/class/powercap/intel-rapl:0/energy_uj)"
		diff=$((E1 - E0))
		[[ $diff -lt 0 ]] && diff="$E1"
		PKG_W_NOW="$(printf "%.2f" "$(awk -v d="$diff" 'BEGIN{print d/2000000.0}')")"
	fi

	# JSON Output
	if $json_out; then
		if ! have jq; then
			echo "${RED}Error: --json requires 'jq'${RST}" >&2
			exit 1
		fi

		GOV_JSON="{}"
		if ((GOV_COUNT > 0)); then
			for k in "${!GOV_MAP[@]}"; do
				GOV_JSON="$(jq -cn --argjson cur "$GOV_JSON" --arg k "$k" \
					--argjson v "${GOV_MAP[$k]}" '$cur + {($k):$v}')"
			done
		fi

		EPP_JSON="{}"
		if ((EPP_COUNT > 0)); then
			for k in "${!EPP_MAP[@]}"; do
				EPP_JSON="$(jq -cn --argjson cur "$EPP_JSON" --arg k "$k" \
					--argjson v "${EPP_MAP[$k]}" '$cur + {($k):$v}')"
			done
		fi

		TS="$(date +%Y-%m-%dT%H:%M:%S%z)"

		jq -n \
			--arg version "$VERSION" \
			--arg cpu_type "$CPU_TYPE" \
			--arg power_source "$POWER_SRC" \
			--arg load1 "$LOAD1" \
			--arg governor "$GOVERNOR_ANY" \
			--arg governor_cpu0 "$GOVERNOR_CPU0" \
			--arg governor_desired "$GOVERNOR_DESIRED" \
			--arg pstate "$PSTATE" \
			--arg epp_any "$EPP_ANY" \
			--arg epp_desired "$EPP_DESIRED" \
				--arg platform_profile "$PLATFORM_PROFILE_SYSFS" \
				--arg platform_profile_desired "$PLATFORM_PROFILE_DESIRED" \
				--arg mmio_status "$MMIO_STATUS" \
				--arg ppd_profile "$PPD_CURRENT" \
				--arg ppd_load "$PPD_LOAD" \
				--arg ppd_state "$PPD_STATE" \
				--arg ppd_substate "$PPD_SUBSTATE" \
				--arg ppd_result "$PPD_RESULT" \
				--arg ppp_timer_load "$PPP_TIMER_LOAD" \
				--arg ppp_timer_state "$PPP_TIMER_STATE" \
				--arg ppp_timer_substate "$PPP_TIMER_SUBSTATE" \
				--arg ppp_timer_result "$PPP_TIMER_RESULT" \
				--arg ppp_service_load "$PPP_SERVICE_LOAD" \
				--arg ppp_service_state "$PPP_SERVICE_STATE" \
				--arg ppp_service_substate "$PPP_SERVICE_SUBSTATE" \
				--arg ppp_service_result "$PPP_SERVICE_RESULT" \
				--arg ppp_lock_profile "$PPP_LOCK_PROFILE" \
				--arg ts "$TS" \
				--argjson user_systemd_available "$([[ "$USER_SYSTEMD_AVAILABLE" == true ]] && echo true || echo false)" \
				--argjson ppp_locked "$([[ "$PPP_LOCKED" == true ]] && echo true || echo false)" \
				--argjson turbo "$TURBO_ENABLED" \
				--argjson hwp_boost "$HWP_BOOST_BOOL" \
				--argjson mmio_loaded "$MMIO_LOADED" \
			--argjson min_perf "${MIN_PERF//[^0-9]/}" \
			--argjson max_perf "${MAX_PERF//[^0-9]/}" \
			--argjson freq_avg "$FREQ_AVG_MHZ" \
			--argjson freq_avg_cpuinfo "${CPUINFO_FREQ_AVG_MHZ//[^0-9]/}" \
			--argjson temp "$TEMP_C" \
			--argjson pl1 "$PL1_W" \
			--argjson pl2 "$PL2_W" \
			--argjson pl4 "$PL4_W" \
			--argjson base_pl2 "$BASE_PL2_W" \
			--argjson pkg_w_now "${PKG_W_NOW:-0}" \
			--argjson bat "$([[ "${BAT_JSON}" == "[]" ]] && echo "[]" || echo "${BAT_JSON}")" \
			--argjson governor_map "$([[ $GOV_COUNT -gt 0 ]] && echo "${GOV_JSON}" || echo "{}")" \
			--argjson epp_map "$([[ $EPP_COUNT -gt 0 ]] && echo "${EPP_JSON}" || echo "{}")" \
			'{
        version: $version,
        cpu_type: $cpu_type,
        power_source: $power_source,
        load_1m: ($load1|tonumber),
        governor: $governor,
        governor_cpu0: $governor_cpu0,
        governor_desired: $governor_desired,
        governor_map: $governor_map,
        pstate_mode: $pstate,
        epp_any: $epp_any,
        epp_desired: $epp_desired,
        epp_map: $epp_map,
        hwp_dynamic_boost: $hwp_boost,
        turbo_enabled: $turbo,
        mmio_status: $mmio_status,
        mmio_driver_loaded: $mmio_loaded,
        performance: { min_pct: $min_perf, max_pct: $max_perf },
        platform_profile: $platform_profile,
        platform_profile_desired: $platform_profile_desired,
        freq_avg_mhz: $freq_avg,
        freq_avg_mhz_cpuinfo: $freq_avg_cpuinfo,
        temp_celsius: $temp,
	        power_limits: {
	          pl1_watts: $pl1,
	          pl2_watts: $pl2,
	          pl4_watts: $pl4,
	          base_pl2_watts: $base_pl2
	        },
	        power_backend: {
	          profile: $ppd_profile,
	          daemon: {
	            load: $ppd_load,
	            state: $ppd_state,
	            substate: $ppd_substate,
	            result: $ppd_result
	          }
	        },
	        ppp_auto_profile: {
	          user_systemd_available: $user_systemd_available,
	          timer: {
	            load: $ppp_timer_load,
	            state: $ppp_timer_state,
	            substate: $ppp_timer_substate,
	            result: $ppp_timer_result
	          },
	          service: {
	            load: $ppp_service_load,
	            state: $ppp_service_state,
	            substate: $ppp_service_substate,
	            result: $ppp_service_result
	          },
	          lock: {
	            enabled: $ppp_locked,
	            profile: $ppp_lock_profile
	          }
	        },
	        pkg_watts_now: $pkg_w_now,
	        batteries: $bat,
	        timestamp: $ts
      }'
		return 0
	fi

	# Human-readable output
	echo "${BOLD}=== SYSTEM STATUS (v${VERSION}) ===${RST}"
	echo ""

	echo "CPU Type: ${CYN}${CPU_TYPE}${RST}"
	echo -n "Power Source: "
	[[ "$POWER_SRC" = "AC" ]] && echo "${GRN}⚡ AC${RST}" || echo "${YLW}🔋 Battery${RST}"
	echo "Load Avg (1m): ${BOLD}${LOAD1}${RST}"
	echo ""

	if [[ "$PSTATE" != "unknown" ]]; then
		echo "P-State Mode: ${BOLD}${PSTATE}${RST}"
		echo "  Min/Max Performance: ${MIN_PERF}% / ${MAX_PERF}%"
		echo "  Turbo Boost: $([[ "$TURBO_ENABLED" = true ]] && echo "${GRN}✓ Active${RST}" || echo "${RED}✗ Disabled${RST}")"
		echo "  HWP Dynamic Boost: $([[ "$HWP_BOOST_BOOL" = true ]] && echo "${GRN}✓ Active${RST}" || echo "${RED}✗ Disabled${RST}")"
		if [[ "$GOVERNOR_ANY" != "unknown" ]]; then
			echo "  Governor: ${GOVERNOR_ANY}"
			[[ "$GOVERNOR_DESIRED" != "unknown" ]] && echo "  Governor (desired): ${GOVERNOR_DESIRED}"
			if ((GOV_COUNT > 0)); then
				echo "  Governor policies:"
				for k in "${!GOV_MAP[@]}"; do
					echo "    ${CYN}→${RST} ${BOLD}${k}${RST} (${GOV_MAP[$k]} policies)"
				done
			fi
				if [[ "$GOVERNOR_CPU0" != "unknown" && "$GOVERNOR_CPU0" != "$GOVERNOR_ANY" ]]; then
					echo "  ${DIM}Note: cpu0 reports '${GOVERNOR_CPU0}' (can be misleading on intel_pstate active)${RST}"
				fi
				if [[ "$CPU_TYPE" == "intel" && "$PSTATE" == "active" && "$GOVERNOR_ANY" == "powersave" ]]; then
					echo "  ${DIM}Note: intel_pstate=active'da 'powersave' governor normaldir; gerçek performansı çoğunlukla EPP + min/max perf belirler.${RST}"
				fi
			fi
		fi

		if [[ "$PLATFORM_PROFILE_SYSFS" != "unknown" ]]; then
			echo "Platform Profile: ${BOLD}${PLATFORM_PROFILE_SYSFS}${RST}"
			[[ "$PLATFORM_PROFILE_DESIRED" != "unknown" ]] && echo "Platform Profile (desired): ${BOLD}${PLATFORM_PROFILE_DESIRED}${RST}"
			if [[ -r /sys/firmware/acpi/platform_profile_choices ]]; then
				choices="$(cat /sys/firmware/acpi/platform_profile_choices 2>/dev/null || true)"
				[[ -n "$choices" ]] && echo "  ${DIM}Choices: ${choices}${RST}"
			fi
		fi

	echo ""
	if ((EPP_COUNT > 0)); then
		echo "EPP (Energy Performance Preference):"
		for k in "${!EPP_MAP[@]}"; do
			echo "  ${CYN}→${RST} ${BOLD}${k}${RST} (${EPP_MAP[$k]} policies)"
		done
		[[ "$EPP_DESIRED" != "unknown" ]] && echo "  ${DIM}(desired: ${EPP_DESIRED})${RST}"
	else
		echo "EPP: ${DIM}(interface not found)${RST}"
	fi

	if ! $brief_out; then
		echo ""
		echo "CPU FREQUENCIES:"
		for i in 0 4 8 12 16 20; do
			# Prefer cpuinfo for human display; fall back to sysfs.
			if [[ -n "${CPUINFO_MHZ_BY_CPU[$i]:-}" ]]; then
				printf "  CPU %2d: %4d MHz\n" "$i" "${CPUINFO_MHZ_BY_CPU[$i]%.*}"
				continue
			fi

			p="/sys/devices/system/cpu/cpu${i}/cpufreq/scaling_cur_freq"
			[[ -r "$p" ]] || continue
			f="$(cat "$p" 2>/dev/null || echo 0)"
			printf "  CPU %2d: %4d MHz\n" "$i" "$((f / 1000))"
		done
		echo "  ${DIM}Average: ${BOLD}${FREQ_AVG_MHZ} MHz${RST}"
		if [[ "$CPUINFO_FREQ_AVG_MHZ" != "0" && "$CPUINFO_FREQ_AVG_MHZ" != "$FREQ_AVG_MHZ" ]]; then
			echo "  ${DIM}Average (cpuinfo): ${BOLD}${CPUINFO_FREQ_AVG_MHZ} MHz${RST}"
		fi
		if [[ "$CPU_TYPE" == "intel" && "$PSTATE" == "active" ]]; then
			echo "  ${DIM}💡 Note: Intel HWP'de sysfs frekansları yanıltıcı olabilir; doğrulama için turbostat kullan${RST}"
		else
			echo "  ${DIM}💡 Note: scaling_cur_freq can be misleading; use turbostat${RST}"
		fi

		# If sysfs reports ~400MHz but cpuinfo is clearly higher, call it out loudly.
		if [[ "$FREQ_AVG_MHZ" -le 500 && "$CPUINFO_FREQ_AVG_MHZ" -ge 800 ]]; then
			echo "  ${YLW}⚠ sysfs 400MHz raporlayabiliyor; cpuinfo bunu desteklemiyor (muhtemelen raporlama artefaktı).${RST}"
		fi

			# If both signals are low while the system is "under load", suggest a deeper check.
			if awk -v l="$LOAD1" -v mhz="${CPUINFO_FREQ_AVG_MHZ:-0}" 'BEGIN{exit !(l>=1.0 && mhz>0 && mhz<=600)}'; then
				echo "  ${YLW}⚠ load yüksek ama CPU MHz düşük görünüyor.${RST}"
				echo "  ${DIM}Bu HWP raporlama artefaktı da olabilir, gerçek throttling de olabilir.${RST}"
				echo "  ${DIM}→ Doğrulama: sudo ${SUDO_SCRIPT_CMD} turbostat-quick${RST}"
			fi
		fi

	echo ""
	TEMP_COLOR="${GRN}"
	[[ $(awk -v t="$TEMP_C" 'BEGIN{print (t>=70)?1:0}') -eq 1 ]] && TEMP_COLOR="${YLW}"
	[[ $(awk -v t="$TEMP_C" 'BEGIN{print (t>=80)?1:0}') -eq 1 ]] && TEMP_COLOR="${RED}"
	echo "TEMPERATURE: ${TEMP_COLOR}${BOLD}${TEMP_C}°C${RST}"

	echo ""
		echo "RAPL POWER LIMITS (MSR):"
	if [[ -d /sys/class/powercap/intel-rapl:0 ]]; then
		printf "  PL1 (sustained): ${BOLD}%2d W${RST}\n" "$PL1_W"
		[[ $PL1_MAX_W -gt 0 ]] && printf "  ${DIM}PL1 max (platform): %2d W${RST}\n" "$PL1_MAX_W"
		printf "  PL2 (burst):     ${BOLD}%2d W${RST}\n" "$PL2_W"
		[[ $PL2_MAX_W -gt 0 ]] && printf "  ${DIM}PL2 max (platform): %2d W${RST}\n" "$PL2_MAX_W"
		[[ $PL4_W -gt 0 ]] && printf "  PL4 (peak):      ${BOLD}%2d W${RST}\n" "$PL4_W"
		[[ $BASE_PL2_W -gt 0 ]] && echo "  ${DIM}Base PL2 (thermal guard ref): ${BASE_PL2_W} W${RST}"

		echo ""
		echo "  MMIO Driver: $([[ "$MMIO_LOADED" = true ]] && echo "${RED}✗ ACTIVE (WARNING!)${RST}" || echo "${GRN}✓ DISABLED${RST}")"
		if [[ "$MMIO_LOADED" = true ]]; then
			echo "  ${RED}⚠ MMIO driver loaded! MSR/MMIO conflict possible${RST}"
			echo "  ${YLW}→ Fix: sudo systemctl restart disable-rapl-mmio.service${RST}"
		fi

		if $sample_power && [[ -n "${PKG_W_NOW}" ]]; then
			echo ""
			echo "  Instant Package Power (~2s sample): ${BOLD}${PKG_W_NOW} W${RST}"
		fi

		echo ""
		if [[ "$POWER_SRC" = "AC" ]]; then
			echo "  ${GRN}💡 AC mode - Performance limits${RST}"
		else
			echo "  ${YLW}💡 Battery mode - Efficiency limits${RST}"
		fi
	else
		echo "  ${RED}RAPL interface not found${RST}"
	fi

	echo ""
	echo "BATTERY STATUS:"
	((${#BAT_LINES[@]} == 0)) && echo "  ${DIM}No battery detected${RST}" || printf "%s\n" "${BAT_LINES[@]}"

	echo ""
		echo "SERVICE STATUS:"
		if [[ -z "$PPD_LOAD" ]]; then
			echo "  power-profiles-daemon          ${DIM}– systemd unavailable in this session${RST}"
		elif [[ "$PPD_LOAD" == "not-found" ]]; then
			echo "  power-profiles-daemon          ${RED}✗ NOT INSTALLED${RST}"
		elif [[ "$PPD_STATE" == "active" ]]; then
			printf "  %-30s ${GRN}✓ ACTIVE${RST} ${DIM}(%s)${RST}\n" "power-profiles-daemon" "${PPD_SUBSTATE:-running}"
		elif [[ "$PPD_STATE" == "inactive" ]]; then
			printf "  %-30s ${YLW}⚠ INACTIVE${RST} ${DIM}(%s)${RST}\n" "power-profiles-daemon" "${PPD_RESULT:-unknown}"
		else
			printf "  %-30s ${RED}✗ %s${RST} ${DIM}(%s)${RST}\n" "power-profiles-daemon" "${PPD_STATE:-unknown}" "${PPD_RESULT:-unknown}"
		fi
		[[ "$PPD_CURRENT" != "unknown" ]] && echo "    ${DIM}Current profile: ${PPD_CURRENT}${RST}"

		if [[ "$USER_SYSTEMD_AVAILABLE" == true ]]; then
			if [[ -z "$PPP_TIMER_LOAD" || "$PPP_TIMER_LOAD" == "not-found" ]]; then
				echo "  ppp-auto-profile.timer         ${DIM}– not installed${RST}"
			elif [[ "$PPP_TIMER_STATE" == "active" ]]; then
				printf "  %-30s ${GRN}✓ ACTIVE${RST} ${DIM}(%s)${RST}\n" "ppp-auto-profile.timer" "${PPP_TIMER_SUBSTATE:-waiting}"
			elif [[ "$PPP_TIMER_STATE" == "inactive" ]]; then
				printf "  %-30s ${YLW}⚠ INACTIVE${RST} ${DIM}(auto-switch disabled)${RST}\n" "ppp-auto-profile.timer"
			else
				printf "  %-30s ${RED}✗ %s${RST} ${DIM}(%s)${RST}\n" "ppp-auto-profile.timer" "${PPP_TIMER_STATE:-unknown}" "${PPP_TIMER_RESULT:-unknown}"
			fi

			if [[ -z "$PPP_SERVICE_LOAD" || "$PPP_SERVICE_LOAD" == "not-found" ]]; then
				echo "  ppp-auto-profile.service       ${DIM}– not installed${RST}"
			elif [[ "$PPP_SERVICE_STATE" == "active" ]]; then
				printf "  %-30s ${GRN}✓ ACTIVE${RST} ${DIM}(%s)${RST}\n" "ppp-auto-profile.service" "${PPP_SERVICE_SUBSTATE:-running}"
			elif [[ "$PPP_SERVICE_STATE" == "inactive" && "$PPP_SERVICE_RESULT" == "success" ]]; then
				printf "  %-30s ${GRN}✓ OK${RST} ${DIM}(oneshot completed)${RST}\n" "ppp-auto-profile.service"
			else
				printf "  %-30s ${RED}✗ %s${RST} ${DIM}(%s)${RST}\n" "ppp-auto-profile.service" "${PPP_SERVICE_STATE:-unknown}" "${PPP_SERVICE_RESULT:-unknown}"
			fi
		else
			echo "  ppp-auto-profile               ${DIM}– user systemd unavailable in this session${RST}"
		fi

		if [[ "$PPP_LOCKED" == true ]]; then
			if [[ -n "$PPP_LOCK_PROFILE" ]]; then
				echo "  auto-profile lock              ${YLW}⚠ LOCKED${RST} ${DIM}(${PPP_LOCK_PROFILE})${RST}"
			else
				echo "  auto-profile lock              ${YLW}⚠ LOCKED${RST}"
			fi
		else
			echo "  auto-profile lock              ${GRN}✓ unlocked${RST}"
		fi

		echo ""
		echo "POTENTIAL CONFLICTS:"
		CONFLICTS=(auto-cpufreq tlp thermald tuned)
		found_any=0
		for svc in "${CONFLICTS[@]}"; do
			if systemctl list-unit-files "${svc}.service" >/dev/null 2>&1; then
				found_any=1
				if systemctl is-active --quiet "${svc}.service" 2>/dev/null; then
					echo "  ${YLW}⚠ ${svc}${RST}: ${YLW}ACTIVE${RST} (power ayarlarını override edebilir)"
				else
					echo "  ${DIM}${svc}${RST}: inactive"
				fi
			fi
		done
		[[ "$found_any" = "0" ]] && echo "  ${DIM}(none detected)${RST}"

		echo ""
		echo "${DIM}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RST}"
		echo "${BOLD}💡 Tips:${RST}"
		echo "  • Real CPU frequencies: ${CYN}${SCRIPT_NAME} turbostat-quick${RST}"
	echo "  • Power consumption:    ${CYN}${SCRIPT_NAME} power-check${RST} / ${CYN}${SCRIPT_NAME} power-monitor${RST}"
	echo "  • Thermal monitoring:   ${CYN}${SCRIPT_NAME} thermal -d 300 -p${RST}"
	echo "  • JSON output:          ${CYN}${SCRIPT_NAME} status --json${RST}"
	echo "  • Power sample:         ${CYN}${SCRIPT_NAME} status --sample-power${RST}"
}

# ==============================================================================
# COMMAND: thermal
# ==============================================================================
THERMAL_DURATION=60
THERMAL_INTERVAL=2
THERMAL_OUTPUT=""
THERMAL_PLOT=0
THERMAL_SHOW_LIVE=1

show_thermal_help() {
	cat <<EOF
${BOLD}${CYN}Thermal Monitor${RST} - Comprehensive thermal & power logging

${BOLD}Usage:${RST} ${SCRIPT_NAME} thermal [OPTIONS]

${BOLD}Options:${RST}
  -d, --duration SECONDS    Monitor duration in seconds (default: 60)
  -i, --interval SECONDS    Sample interval in seconds (default: 2)
  -o, --output FILE         Output CSV file (default: ${THERMAL_LOG_DIR}/thermal-TIMESTAMP.csv)
  -p, --plot                Generate gnuplot graph after logging
  -q, --quiet               Disable live output, only log to file
  -h, --help                Show this help

${BOLD}Examples:${RST}
  ${SCRIPT_NAME} thermal                        # 60s monitoring
  ${SCRIPT_NAME} thermal -d 300 -i 5            # 5 min, 5s interval
  ${SCRIPT_NAME} thermal -d 120 -p              # 2 min with plot
  ${SCRIPT_NAME} thermal -d 3600 -i 10 -q       # 1 hour silent

${BOLD}Output Format (CSV):${RST}
  timestamp,temp_c,pl1_w,pl2_w,fan_rpm,avg_mhz,pkg_watt

${BOLD}Logged Data:${RST}
  • CPU Package Temperature (°C)
  • RAPL Power Limits (PL1/PL2 in Watts)
  • Fan Speed (RPM)
  • Average CPU Frequency (MHz)
  • Package Power Consumption (Watts via RAPL)

${BOLD}Notes:${RST}
  • All logs saved to: ${THERMAL_LOG_DIR}/
  • No root required (uses RAPL energy counters)
  • Plotting requires gnuplot (e.g. 'nix-shell -p gnuplot' veya flake'e ekle)

EOF
}

read_temp_thermal() {
	sensors 2>/dev/null | grep "Package id 0" | grep -oP '\+\K[0-9]+' | head -1 || echo "0"
}

read_pl1() {
	[[ -r /sys/class/powercap/intel-rapl:0/constraint_0_power_limit_uw ]] &&
		awk '{print int($1/1000000)}' /sys/class/powercap/intel-rapl:0/constraint_0_power_limit_uw || echo "0"
}

read_pl2() {
	[[ -r /sys/class/powercap/intel-rapl:0/constraint_1_power_limit_uw ]] &&
		awk '{print int($1/1000000)}' /sys/class/powercap/intel-rapl:0/constraint_1_power_limit_uw || echo "0"
}

read_fan() {
	[[ -r /proc/acpi/ibm/fan ]] &&
		grep "speed:" /proc/acpi/ibm/fan 2>/dev/null | awk '{print $2}' || echo "0"
}

read_power_rapl() {
	local ENERGY_FILE="/sys/class/powercap/intel-rapl:0/energy_uj"
	[[ ! -r "$ENERGY_FILE" ]] && {
		echo "0"
		return
	}

	local ENERGY_BEFORE=$(cat "$ENERGY_FILE")
	sleep 0.5
	local ENERGY_AFTER=$(cat "$ENERGY_FILE")

	local ENERGY_DIFF=$((ENERGY_AFTER - ENERGY_BEFORE))
	[[ $ENERGY_DIFF -lt 0 ]] && ENERGY_DIFF=$ENERGY_AFTER

	echo "scale=2; $ENERGY_DIFF / 500000" | bc
}

read_freq_thermal() {
	local FREQS=($(cat /sys/devices/system/cpu/cpu*/cpufreq/scaling_cur_freq 2>/dev/null || echo "0"))
	if [[ ${#FREQS[@]} -gt 0 ]]; then
		local SUM=$(
			IFS=+
			echo "$((${FREQS[*]}))"
		)
		echo $((SUM / ${#FREQS[@]} / 1000))
	else
		echo "0"
	fi
}

colorize_temp() {
	local temp=$1
	((temp >= 80)) && echo -e "${RED}${temp}°C${RST}" && return
	((temp >= 70)) && echo -e "${YLW}${temp}°C${RST}" && return
	echo -e "${GRN}${temp}°C${RST}"
}

colorize_power() {
	local power=$1
	(($(echo "$power >= 35" | bc -l))) && echo -e "${RED}${power}W${RST}" && return
	(($(echo "$power >= 20" | bc -l))) && echo -e "${YLW}${power}W${RST}" && return
	echo -e "${GRN}${power}W${RST}"
}

parse_thermal_args() {
	while [[ $# -gt 0 ]]; do
		case "$1" in
		-d | --duration)
			THERMAL_DURATION="$2"
			shift 2
			;;
		-i | --interval)
			THERMAL_INTERVAL="$2"
			shift 2
			;;
		-o | --output)
			THERMAL_OUTPUT="$2"
			shift 2
			;;
		-p | --plot)
			THERMAL_PLOT=1
			shift
			;;
		-q | --quiet)
			THERMAL_SHOW_LIVE=0
			shift
			;;
		-h | --help)
			show_thermal_help
			exit 0
			;;
		*)
			echo -e "${RED}Unknown thermal option: $1${RST}"
			show_thermal_help
			exit 1
			;;
		esac
	done
}

cmd_thermal() {
	parse_thermal_args "$@"

	ensure_log_dir "$THERMAL_LOG_DIR"
	[[ -z "$THERMAL_OUTPUT" ]] && THERMAL_OUTPUT="${THERMAL_LOG_DIR}/thermal-$(date +%Y%m%d_%H%M%S).csv"

	SAMPLES=$((THERMAL_DURATION / THERMAL_INTERVAL))
	((SAMPLES == 0)) && SAMPLES=1
	CURRENT=0

	echo "timestamp,temp_c,pl1_w,pl2_w,fan_rpm,avg_mhz,pkg_watt" >"$THERMAL_OUTPUT"

	if [[ $THERMAL_SHOW_LIVE -eq 1 ]]; then
		echo -e "${CYN}=== Thermal Monitoring Started ===${RST}"
		echo -e "Duration: ${THERMAL_DURATION}s | Interval: ${THERMAL_INTERVAL}s | Samples: ${SAMPLES}"
		echo -e "Output:   ${THERMAL_OUTPUT}"
		[[ $EUID -ne 0 ]] && echo -e "${YLW}Note: Using RAPL for power measurements (no root required)${RST}"
		echo ""
		printf "%-8s %-10s %-10s %-8s %-8s %-10s %-12s\n" \
			"Sample" "Time" "Temp" "PL1" "PL2" "Fan" "PkgWatt"
		echo "-------------------------------------------------------------------------------"
	fi

	while [[ $CURRENT -lt $SAMPLES ]]; do
		CURRENT=$((CURRENT + 1))
		TIMESTAMP=$(date +%s)
		TIME_STR=$(date +%H:%M:%S)

		TEMP=$(read_temp_thermal)
		PL1=$(read_pl1)
		PL2=$(read_pl2)
		FAN=$(read_fan)
		AVG_MHZ=$(read_freq_thermal)
		PKG_WATT=$(read_power_rapl)

		echo "${TIMESTAMP},${TEMP},${PL1},${PL2},${FAN},${AVG_MHZ},${PKG_WATT}" >>"$THERMAL_OUTPUT"

		if [[ $THERMAL_SHOW_LIVE -eq 1 ]]; then
			TEMP_COLOR=$(colorize_temp "$TEMP")
			POWER_COLOR=$(colorize_power "$PKG_WATT")
			printf "%-8s %-10s %-10s %-8s %-8s %-10s %-12s\n" \
				"$CURRENT" "$TIME_STR" "$TEMP_COLOR" "${PL1}W" "${PL2}W" "${FAN}rpm" "$POWER_COLOR"
		fi

		sleep "$THERMAL_INTERVAL"
	done

	if [[ $THERMAL_SHOW_LIVE -eq 1 ]]; then
		echo ""
		echo -e "${CYN}=== Monitoring Complete ===${RST}"
		echo ""

		read -r MIN_TEMP AVG_TEMP MAX_TEMP AVG_PL2 AVG_FAN AVG_PWR MIN_PWR MAX_PWR <<<"$(awk -F, 'NR>1 {
      if (NR==2 || $2<mint) mint=$2;
      if (NR==2 || $2>maxt) maxt=$2;
      if (NR==2 || $7<minp) minp=$7;
      if (NR==2 || $7>maxp) maxp=$7;
      sumt+=$2; pl2+=$4; fan+=$5; pwr+=$7; count++
    } END {
      if (count==0) {print 0,0,0,0,0,0,0,0; exit}
      printf "%.0f %.1f %.0f %.1f %.0f %.2f %.2f %.2f", mint, sumt/count, maxt, pl2/count, fan/count, pwr/count, minp, maxp
    }' "$THERMAL_OUTPUT")"

		echo "Temperature:"
		echo "  Min:     ${MIN_TEMP}°C"
		echo "  Average: ${AVG_TEMP}°C"
		echo "  Max:     ${MAX_TEMP}°C"
		echo ""
		echo "Package Power (RAPL):"
		echo "  Min:     ${MIN_PWR}W"
		echo "  Average: ${AVG_PWR}W"
		echo "  Max:     ${MAX_PWR}W"
		echo ""
		echo "Limits & Fan:"
		echo "  Avg PL2: ${AVG_PL2}W"
		echo "  Avg Fan: ${AVG_FAN} RPM"
		echo ""
		echo "Log saved to: $THERMAL_OUTPUT"
	fi

	if [[ $THERMAL_PLOT -eq 1 ]]; then
		if ! have gnuplot; then
			echo -e "${YLW}Warning: gnuplot not found. Skipping plot.${RST}"
			echo "Use: nix-shell -p gnuplot (veya flake'e ekle)"
		else
			PLOT_FILE="${THERMAL_OUTPUT%.csv}.png"

			gnuplot <<EOF
set terminal pngcairo size 1400,900 enhanced font 'Arial,11'
set output '${PLOT_FILE}'
set datafile separator ","
set title "Thermal & Power Monitoring - $(basename ${THERMAL_OUTPUT%.csv})" font 'Arial,14'
set xlabel "Time (seconds)" font 'Arial,12'
set ylabel "Temperature (°C)" textcolor rgb "red" font 'Arial,12'
set y2label "Power (W) / Fan (RPM/10)" textcolor rgb "blue" font 'Arial,12'
set y2tics
set ytics nomirror
set grid
set key outside right top vertical font 'Arial,10'

set style line 1 lc rgb '#d62728' lt 1 lw 2.5
set style line 2 lc rgb '#1f77b4' lt 1 lw 2
set style line 3 lc rgb '#ff7f0e' lt 1 lw 2
set style line 4 lc rgb '#2ca02c' lt 1 lw 1.5
set style line 5 lc rgb '#9467bd' lt 1 lw 2

first_ts = 0
plot '${THERMAL_OUTPUT}' using ( (first_ts==0 ? (first_ts=\$1,\$1) : (\$1-first_ts)) ):(column(2)) with lines ls 1 title "Temp (°C)" axes x1y1, \
     '' using ( (first_ts==0 ? (first_ts=\$1,\$1) : (\$1-first_ts)) ):(column(4)) with lines ls 2 title "PL2 (W)" axes x1y2, \
     '' using ( (first_ts==0 ? (first_ts=\$1,\$1) : (\$1-first_ts)) ):(column(3)) with lines ls 3 title "PL1 (W)" axes x1y2, \
     '' using ( (first_ts==0 ? (first_ts=\$1,\$1) : (\$1-first_ts)) ):(column(7)) with lines ls 5 title "Pkg Power (W)" axes x1y2, \
     '' using ( (first_ts==0 ? (first_ts=\$1,\$1) : (\$1-first_ts)) ):(column(5)/10) with lines ls 4 title "Fan (RPM/10)" axes x1y2
EOF

			[[ $THERMAL_SHOW_LIVE -eq 1 ]] && echo -e "${GRN}Plot saved to: ${PLOT_FILE}${RST}"
		fi
	fi
}

# ==============================================================================
# COMMAND: turbostat-quick
# ==============================================================================
cmd_turbostat_quick() {
	if [[ "${1:-}" == "--help" ]] || [[ "${1:-}" == "-h" ]]; then
		cat <<EOF
${BOLD}Turbostat Quick${RST} - Real CPU frequency analysis

${BOLD}Usage:${RST} sudo ${SUDO_SCRIPT_CMD} turbostat-quick

Real CPU frequency analysis using turbostat.
Shows actual CPU behavior by reading hardware counters.

${BOLD}Key metrics:${RST}
  • Avg_MHz: True average frequency (including idle time)
  • Bzy_MHz: Average frequency of non-idle cores
  • PkgWatt: Total power consumption of CPU package

${BOLD}Note:${RST} Requires root to access Model-Specific Registers (MSRs)

EOF
		return 0
	fi

	echo "=== TURBOSTAT QUICK ANALYSIS (5 seconds) ==="
	echo ""
	echo "NOTE: 'Avg_MHz' is the true average frequency. 'Bzy_MHz' is frequency when busy."
	echo "      scaling_cur_freq from sysfs may show 400 MHz; ignore it under HWP."
	echo ""

	if ! have turbostat; then
		echo "${RED}⚠ turbostat not found.${RST}"
		echo "Tip: install turbostat to enable power telemetry"
		exit 1
	fi

	if [[ $EUID -ne 0 ]]; then
		echo "${RED}⚠ This command requires root privileges to read MSRs.${RST}"
		echo "   Please run: sudo ${SUDO_SCRIPT_CMD} turbostat-quick"
		exit 1
	fi

	turbostat --interval 5 --num_iterations 1
}

# ==============================================================================
# COMMAND: turbostat-stress
# ==============================================================================
cmd_turbostat_stress() {
	ANALYZE=0
	while [[ $# -gt 0 ]]; do
		case "$1" in
		--analyze)
			ANALYZE=1
			shift
			;;
		-h | --help)
			cat <<EOF
${BOLD}Turbostat Stress${RST} - Performance testing under load

${BOLD}Usage:${RST} sudo ${SUDO_SCRIPT_CMD} turbostat-stress [--analyze]

Runs stress test while monitoring CPU behavior with turbostat.

${BOLD}Options:${RST}
  --analyze    Parse output and generate statistics
  -h, --help   Show this help

${BOLD}What it does:${RST}
  1. Starts turbostat logging (10s interval, 3 iterations = 30s)
  2. Immediately launches stress-ng (all cores, 30s)
  3. Monitors frequency, power, and thermals

${BOLD}Requirements:${RST}
  • Root privileges (for turbostat MSR access)
  • stress-ng package installed

EOF
			return 0
			;;
		*)
			echo "${RED}Unknown option: $1${RST}"
			return 1
			;;
		esac
		shift
	done

	if ! have turbostat || ! have stress-ng; then
		echo "${RED}⚠ Required tools missing${RST}"
		echo "turbostat: $(have turbostat && echo "✓" || echo "✗")"
		echo "stress-ng: $(have stress-ng && echo "✓" || echo "✗")"
		exit 1
	fi

	if [[ $EUID -ne 0 ]]; then
		echo "${RED}⚠ Root required. Run: sudo ${SUDO_SCRIPT_CMD} turbostat-stress${RST}"
		exit 1
	fi

	echo "=== TURBOSTAT STRESS TEST ==="
	echo "Starting stress-ng on all cores for 30 seconds..."
	echo ""

	LOGFILE=$(mktemp)
	turbostat --interval 10 --num_iterations 3 2>&1 | tee "$LOGFILE" &
	TURBO_PID=$!

	sleep 2
	stress-ng --cpu 0 --timeout 30s --metrics-brief >/dev/null 2>&1 &

	wait $TURBO_PID

	if [[ $ANALYZE -eq 1 ]]; then
		echo ""
		echo "=== ANALYSIS ==="
		awk '/^[^C]/ && NF>5 && $2 ~ /^[0-9]+$/ {
      if (max_freq < $5) max_freq = $5;
      if (max_watts < $11) max_watts = $11;
    } END {
      printf "Peak Bzy_MHz: %.0f MHz\n", max_freq;
      printf "Peak PkgWatt: %.2f W\n", max_watts;
    }' "$LOGFILE"
	fi

	rm -f "$LOGFILE"
}

# ==============================================================================
# COMMAND: turbostat-analyze
# ==============================================================================
cmd_turbostat_analyze() {
	INTERVAL=2
	ITERS=3

	while [[ $# -gt 0 ]]; do
		case "$1" in
		--interval)
			INTERVAL="$2"
			shift 2
			;;
		--iters)
			ITERS="$2"
			shift 2
			;;
		-h | --help)
			cat <<EOF
${BOLD}Turbostat Analyze${RST} - Parse and analyze turbostat output

${BOLD}Usage:${RST} sudo ${SUDO_SCRIPT_CMD} turbostat-analyze [OPTIONS]

${BOLD}Options:${RST}
  --interval SECS    Sample interval (default: 2)
  --iters NUM        Number of iterations (default: 3)
  -h, --help         Show this help

${BOLD}Features:${RST}
  • Runs turbostat with specified parameters
  • Parses output for min/max/avg statistics
  • Shows frequency and power analysis

${BOLD}Example:${RST}
  sudo ${SUDO_SCRIPT_CMD} turbostat-analyze --interval 1 --iters 5

EOF
			return 0
			;;
		*)
			echo "${RED}Unknown option: $1${RST}"
			return 1
			;;
		esac
		shift
	done

	if ! have turbostat; then
		echo "${RED}⚠ turbostat not found${RST}"
		exit 1
	fi

	if [[ $EUID -ne 0 ]]; then
		echo "${RED}⚠ Root required${RST}"
		exit 1
	fi

	echo "=== TURBOSTAT ANALYSIS ==="
	echo "Interval: ${INTERVAL}s | Iterations: ${ITERS}"
	echo ""

	LOGFILE=$(mktemp)
	turbostat --interval "$INTERVAL" --num_iterations "$ITERS" 2>&1 | tee "$LOGFILE"

	echo ""
	echo "=== SUMMARY ==="
	awk '/^[^C]/ && NF>5 && $2 ~ /^[0-9]+$/ {
    freq[NR] = $5; watt[NR] = $11; n++;
  } END {
    if (n == 0) exit;
    for (i=1; i<=n; i++) {
      sum_f += freq[i]; sum_w += watt[i];
      if (freq[i] > max_f) max_f = freq[i];
      if (freq[i] < min_f || min_f == 0) min_f = freq[i];
      if (watt[i] > max_w) max_w = watt[i];
      if (watt[i] < min_w || min_w == 0) min_w = watt[i];
    }
    printf "Bzy_MHz: Min=%.0f Avg=%.0f Max=%.0f\n", min_f, sum_f/n, max_f;
    printf "PkgWatt: Min=%.2f Avg=%.2f Max=%.2f\n", min_w, sum_w/n, max_w;
  }' "$LOGFILE"

	rm -f "$LOGFILE"
}

# ==============================================================================
# COMMAND: power-check
# ==============================================================================
cmd_power_check() {
	if [[ "${1:-}" == "--help" ]] || [[ "${1:-}" == "-h" ]]; then
		cat <<EOF
${BOLD}Power Check${RST} - Measure instantaneous power consumption

${BOLD}Usage:${RST} ${SCRIPT_NAME} power-check

Measures CPU package power consumption over a 2-second interval using RAPL.

${BOLD}Features:${RST}
  • No root required (uses RAPL energy counters)
  • Shows current power draw in Watts
  • Displays active RAPL limits (PL1/PL2)
  • Power source detection (AC/Battery)

EOF
		return 0
	fi

	echo "=== INSTANTANEOUS POWER CONSUMPTION CHECK ==="
	echo ""

	ON_AC=0
	for PS in /sys/class/power_supply/AC*/online /sys/class/power_supply/ADP*/online; do
		[[ -f "$PS" ]] && {
			ON_AC="$(cat "$PS")"
			break
		}
	done
	[[ "${ON_AC}" = "1" ]] && echo "Power Source: ${GRN}⚡ AC Power${RST}" || echo "Power Source: ${YLW}🔋 Battery${RST}"
	echo ""

	if [[ ! -f /sys/class/powercap/intel-rapl:0/energy_uj ]]; then
		echo "${RED}⚠ RAPL interface not found. Cannot measure power.${RST}"
		exit 1
	fi

	echo "Measuring power consumption over a 2-second interval..."
	ENERGY_BEFORE=$(cat /sys/class/powercap/intel-rapl:0/energy_uj)
	sleep 2
	ENERGY_AFTER=$(cat /sys/class/powercap/intel-rapl:0/energy_uj)

	ENERGY_DIFF=$((ENERGY_AFTER - ENERGY_BEFORE))
	[[ "${ENERGY_DIFF}" -lt 0 ]] && ENERGY_DIFF="${ENERGY_AFTER}"

	WATTS=$(echo "scale=2; ${ENERGY_DIFF} / 2000000" | bc)

	echo ""
	echo ">> INSTANTANEOUS PACKAGE POWER: ${BOLD}${WATTS} W${RST}"
	echo ""

	PL1=$(cat /sys/class/powercap/intel-rapl:0/constraint_0_power_limit_uw)
	PL2=$(cat /sys/class/powercap/intel-rapl:0/constraint_1_power_limit_uw)
	printf "Active RAPL Limits:\n  PL1 (Sustained): %3d W\n  PL2 (Burst):     %3d W\n\n" $((PL1 / 1000000)) $((PL2 / 1000000))

	WATTS_INT=$(echo "${WATTS}" | cut -d. -f1)
	if [[ "${WATTS_INT}" -lt 10 ]]; then
		echo "📊 Status: ${GRN}Idle or light usage${RST}"
	elif [[ "${WATTS_INT}" -lt 30 ]]; then
		echo "📊 Status: ${GRN}Normal productivity workload${RST}"
	elif [[ "${WATTS_INT}" -lt 50 ]]; then
		echo "📊 Status: ${YLW}High load (compiling, gaming)${RST}"
	else
		echo "📊 Status: ${RED}Very high load (stress test)${RST}"
	fi
}

# ==============================================================================
# COMMAND: power-monitor
# ==============================================================================
cmd_power_monitor() {
	if [[ "${1:-}" == "--help" ]] || [[ "${1:-}" == "-h" ]]; then
		cat <<EOF
${BOLD}Power Monitor${RST} - Real-time power monitoring dashboard

${BOLD}Usage:${RST} ${SCRIPT_NAME} power-monitor

Continuously updates every second showing:
  • Power source (AC/Battery)
  • Current EPP setting
  • Package temperature
  • RAPL power consumption
  • CPU frequency statistics

${BOLD}Controls:${RST}
  Press Ctrl+C to stop monitoring

${BOLD}Note:${RST} No root required (uses RAPL energy counters)

EOF
		return 0
	fi

	trap "tput cnorm; exit" INT
	tput civis

	while true; do
		clear
		echo "${BOLD}=== REAL-TIME POWER MONITOR (v${VERSION}) | Press Ctrl+C to stop ===${RST}"
		echo "Timestamp: $(date '+%H:%M:%S')"
		echo "------------------------------------------------------------"

		ON_AC=0
		for PS in /sys/class/power_supply/AC*/online /sys/class/power_supply/ADP*/online; do
			[[ -f "$PS" ]] && {
				ON_AC="$(cat "$PS")"
				break
			}
		done
		[[ "${ON_AC}" = "1" ]] && echo "Power Source:  ${GRN}⚡ AC Power${RST}" || echo "Power Source:  ${YLW}🔋 Battery${RST}"

		EPP=$(cat /sys/devices/system/cpu/cpufreq/policy0/energy_performance_preference 2>/dev/null || echo "N/A")
		echo "EPP Setting:   ${EPP}"

		if have sensors; then
			TEMP=$(sensors 2>/dev/null | grep "Package id 0" | awk '{match($0, /[+]?([0-9]+\.[0-9]+)/, a); print a[1]}')
			[[ -n "${TEMP}" ]] && printf "Temperature:   %.1f°C\n" "${TEMP}" || echo "Temperature:   N/A"
		else
			echo "Temperature:   N/A"
		fi

		echo "------------------------------------------------------------"

		if [[ -f /sys/class/powercap/intel-rapl:0/energy_uj ]]; then
			ENERGY_BEFORE=$(cat /sys/class/powercap/intel-rapl:0/energy_uj)
			sleep 0.5
			ENERGY_AFTER=$(cat /sys/class/powercap/intel-rapl:0/energy_uj)

			ENERGY_DIFF=$((ENERGY_AFTER - ENERGY_BEFORE))
			[[ "${ENERGY_DIFF}" -lt 0 ]] && ENERGY_DIFF="${ENERGY_AFTER}"
			WATTS=$(echo "scale=2; ${ENERGY_DIFF} / 500000" | bc)

			PL1=$(cat /sys/class/powercap/intel-rapl:0/constraint_0_power_limit_uw 2>/dev/null || echo 0)
			PL2=$(cat /sys/class/powercap/intel-rapl:0/constraint_1_power_limit_uw 2>/dev/null || echo 0)

			echo "PACKAGE POWER (RAPL):"
			printf "  Current Consumption: %6.2f W\n" "${WATTS}"
			printf "  Sustained Limit (PL1): %4d W\n" $((PL1 / 1000000))
			printf "  Burst Limit (PL2):     %4d W\n" $((PL2 / 1000000))
		else
			echo "PACKAGE POWER (RAPL): Not Available"
		fi

		echo "------------------------------------------------------------"
		echo "CPU FREQUENCY (scaling_cur_freq):"
		FREQS=($(cat /sys/devices/system/cpu/cpu*/cpufreq/scaling_cur_freq 2>/dev/null || echo ""))
		if [[ ${#FREQS[@]} -gt 0 ]]; then
			SUM=$(
				IFS=+
				echo "$((${FREQS[*]}))"
			)
			AVG=$((SUM / ${#FREQS[@]} / 1000))
			MIN=$(printf "%s\n" "${FREQS[@]}" | sort -n | head -1)
			MAX=$(printf "%s\n" "${FREQS[@]}" | sort -n | tail -1)
			printf "  Average: %5d MHz\n" "$AVG"
			printf "  Min/Max: %5d / %d MHz\n" "$((MIN / 1000))" "$((MAX / 1000))"
			echo "  ${DIM}(NOTE: This value can be misleading; use turbostat)${RST}"
		else
			echo "  Frequency data not available."
		fi
		sleep 0.5
	done
}

# ==============================================================================
# COMMAND: profile-refresh
# ==============================================================================
cmd_profile_refresh() {
	if [[ "${1:-}" == "--help" ]] || [[ "${1:-}" == "-h" ]]; then
		cat <<EOF
${BOLD}Profile Refresh${RST} - Restart power management services

${BOLD}Usage:${RST} sudo ${SUDO_SCRIPT_CMD} profile-refresh

Restart all custom power management services.
Useful for testing configuration changes or recovering
from a failed state without a full reboot.

${BOLD}Services restarted:${RST}
  • Only tracked services that exist on this host

${BOLD}Note:${RST} Requires root privileges

EOF
		return 0
	fi

	echo "=== RESTARTING POWER PROFILE SERVICES ==="
	echo ""
	if [[ $EUID -ne 0 ]]; then
		echo "${RED}⚠ This command requires root privileges. Please run with sudo.${RST}"
		exit 1
	fi

	SERVICES=(
		"platform-profile.service"
		"cpu-epp.service"
		"cpu-min-freq-guard.service"
		"rapl-power-limits.service"
		"rapl-thermo-guard.service"
		"disable-rapl-mmio.service"
		"battery-thresholds.service"
	)
	RESTARTED=0
	SKIPPED=0
	FAILED=0

	for SVC in "${SERVICES[@]}"; do
		LOAD_STATE="$(systemctl show -p LoadState --value "$SVC" 2>/dev/null || true)"
		if [[ -z "$LOAD_STATE" || "$LOAD_STATE" == "not-found" ]]; then
			printf "Skipping %-31s ... ${DIM}[ NOT INSTALLED ]${RST}\n" "$SVC"
			SKIPPED=$((SKIPPED + 1))
			continue
		fi

		printf "Restarting %-30s ... " "$SVC"
		if systemctl restart "$SVC" 2>/dev/null; then
			echo "${GRN}[ OK ]${RST}"
			RESTARTED=$((RESTARTED + 1))
		else
			echo "${RED}[ FAILED ]${RST}"
			FAILED=$((FAILED + 1))
		fi
	done

	echo ""
	echo "${GRN}✓ Power-related services processed.${RST} ${DIM}(restarted: ${RESTARTED}, skipped: ${SKIPPED}, failed: ${FAILED})${RST}"
	echo "-------------------------------------------------"
	cmd_status --brief
}

# ==============================================================================
# MAIN DISPATCHER
# ==============================================================================
main() {
	if [[ $# -eq 0 ]]; then
		show_help
		exit 0
	fi

	case "$1" in
	status)
		shift
		cmd_status "$@"
		;;
	thermal)
		shift
		cmd_thermal "$@"
		;;
	turbostat-quick)
		shift
		cmd_turbostat_quick "$@"
		;;
	turbostat-stress)
		shift
		cmd_turbostat_stress "$@"
		;;
	turbostat-analyze)
		shift
		cmd_turbostat_analyze "$@"
		;;
	power-check)
		shift
		cmd_power_check "$@"
		;;
	power-monitor)
		shift
		cmd_power_monitor "$@"
		;;
	profile-refresh)
		shift
		cmd_profile_refresh "$@"
		;;
	help | -h | --help) show_help ;;
	*)
		echo "${RED}Error: Unknown command '$1'${RST}" >&2
		echo "" >&2
		show_help
		exit 1
		;;
	esac
}

main "$@"
