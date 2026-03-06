#!/usr/bin/env bash
# ==============================================================================
# Script: osc-soundctl.sh
# Description: HyprFlow PipeWire Audio Switcher for Hyprland/Wayland
# Usage: osc-soundctl.sh [options]
# ==============================================================================

# --- Genel ayarlar (env ile override edilebilir) --------------------------------
DEBUG=${DEBUG:-false}
DEFAULT_VOLUME=${DEFAULT_VOLUME:-15}
DEFAULT_MIC_VOLUME=${DEFAULT_MIC_VOLUME:-5}
VOLUME_STEP=${VOLUME_STEP:-5}
NOTIFICATION_TIMEOUT=${NOTIFICATION_TIMEOUT:-3000}
ENABLE_ICONS=${ENABLE_ICONS:-true}
PREFER_BLUETOOTH=${PREFER_BLUETOOTH:-false}
SAVE_PREFERENCES=${SAVE_PREFERENCES:-true}
EXCLUDE_SINK_REGEX=${EXCLUDE_SINK_REGEX:-"HDMI|DisplayPort"} # HDMI/DP’leri döngüden çıkar
INCLUDE_UNAVAILABLE_SINKS=${INCLUDE_UNAVAILABLE_SINKS:-false}
VERSION="3.3.0"

# --- Kalıcı dosyalar (config yok; sadece state/profiller) -----------------------
CACHE_DIR="${HOME}/.cache/hyprflow"
STATE_FILE="${CACHE_DIR}/audio_state"
PROFILES_DIR="${CACHE_DIR}/profiles"
mkdir -p "${CACHE_DIR}" "${PROFILES_DIR}"

# --- Renkler & ikonlar ----------------------------------------------------------
RED=$(tput setaf 1)
GREEN=$(tput setaf 2)
YELLOW=$(tput setaf 3)
BLUE=$(tput setaf 4)
CYAN=$(tput setaf 6)
MAGENTA=$(tput setaf 5)
BOLD=$(tput bold)
RESET=$(tput sgr0)
ICON_SPEAKER="🔊"
ICON_HEADPHONES="🎧"
ICON_MICROPHONE="🎤"
ICON_BLUETOOTH="🔷"
ICON_CHECK="✓"
ICON_CROSS="✗"
ICON_WARNING="⚠️"

# --- Yardımcılar ----------------------------------------------------------------
debug_print() {
	if [ "${DEBUG}" = true ]; then
		local title="$1"
		shift
		echo
		echo "${BLUE}=========================================${RESET}"
		echo "${CYAN}${title}${RESET}"
		echo "${BLUE}=========================================${RESET}"
		[ $# -gt 0 ] && printf "${GREEN}%s${RESET}\n" "$*"
	fi
}
info() { echo "${CYAN}ℹ $1${RESET}"; }
success() { echo "${GREEN}${ICON_CHECK} $1${RESET}"; }
warning() { echo "${YELLOW}${ICON_WARNING} $1${RESET}"; }
error() { echo "${RED}${ICON_CROSS} Error: $1${RESET}" >&2; }

check_command() {
	if ! command -v "$1" >/dev/null 2>&1; then
		error "$1 is required but not found."
		return 1
	fi
}

	notify() {
		local title="$1" msg="$2" icon="${3:-}"
		info "${title}: ${msg}"
		if command -v notify-send >/dev/null 2>&1; then
			if [ "${ENABLE_ICONS}" = true ] && [ -n "${icon}" ]; then
				notify-send -t "${NOTIFICATION_TIMEOUT}" -i "${icon}" "${title}" "${msg}" 2>/dev/null &
			else
				notify-send -t "${NOTIFICATION_TIMEOUT}" "${title}" "${msg}" 2>/dev/null &
			fi
		fi
	}

# --- Argümanlardan debug & genel opsiyonlar ------------------------------------
SHOW_HELP=false
SHOW_VERSION=false
while [[ $# -gt 0 ]]; do
	case "$1" in
	-d | --debug)
		DEBUG=true
		shift
		;;
	-h | --help)
		SHOW_HELP=true
		shift
		;;
	-v | --version)
		SHOW_VERSION=true
		shift
		;;
	--)
		shift
		break
		;;
	-*)
		warning "Bilinmeyen seçenek: $1"
		shift
		;;
	*) break ;;
	esac
done

# --- Bağımlılıklar --------------------------------------------------------------
check_dependencies() {
	local failed=0
	check_command wpctl || failed=1
	command -v notify-send >/dev/null 2>&1 || warning "notify-send yok; bildirimler sadece terminalde görünecek."
	command -v fzf >/dev/null 2>&1 || debug_print "Bilgi" "fzf yok; interaktif seçim kullanılamaz."
	[ $failed -eq 1 ] && exit 1
}

# --- Kalıcı KV (STATE) ----------------------------------------------------------
save_state() {
	local key="$1" value="$2"
	[ "${SAVE_PREFERENCES}" = true ] || return 0
	[ -n "${value}" ] || return 0
	: >"${STATE_FILE}.tmp"
	if [ -f "${STATE_FILE}" ]; then
		grep -v "^${key}=" "${STATE_FILE}" >>"${STATE_FILE}.tmp" || true
	fi
	echo "${key}=${value}" >>"${STATE_FILE}.tmp"
	mv "${STATE_FILE}.tmp" "${STATE_FILE}"
}
load_state() {
	local key="$1"
	[ -f "${STATE_FILE}" ] || return 0
	local value
	value=$(grep "^${key}=" "${STATE_FILE}" 2>/dev/null | cut -d'=' -f2-)
	if [ -n "${value}" ] && [ "$(echo "${value}" | tr -d '[:space:]')" != "" ]; then
		echo "${value}"
	fi
}
id_in_array() {
	local n="$1"
	shift
	for x in "$@"; do [[ "$x" == "$n" ]] && return 0; done
	return 1
}
__strip() { sed -E 's/^[[:space:]│└┌┐┘├┤┬┴─]+//'; }

# --- İkon/isim yardımcıları -----------------------------------------------------
get_device_icon() {
	local name="$1"
	case "$name" in
	*[Bb]luetooth* | *bluez*) echo "$ICON_BLUETOOTH" ;;
	*[Hh]eadphone* | *[Hh]eadset*) echo "$ICON_HEADPHONES" ;;
	*[Mm]ic* | *[Mm]icrophone*) echo "$ICON_MICROPHONE" ;;
	*) echo "$ICON_SPEAKER" ;;
	esac
}
get_sink_display_name() {
	local raw="$1" id="$2"
	local desc=""
	if [[ -n "${id}" ]]; then
		desc="$(__node_description "${id}")"
		if [[ -z "${desc}" || "${desc}" == "bluez_output."* ]]; then
			desc="$(__node_media_name "${id}")"
			desc="$(echo "${desc}" | sed -E 's/[[:space:]]+(input|output)$//I')"
		fi
	fi
	if [[ -z "${desc}" ]]; then
		desc="$(echo "$raw" | sed -e 's/bluez_output\.//; s/alsa_output\.//; s/\.analog-stereo//; s/[[:space:]]+$//')"
	fi
	desc="$(echo "${desc}" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')"
	local icon
	if echo "${raw} ${desc}" | grep -qiE 'bluez|bluetooth|([0-9A-F]{2}:){5}[0-9A-F]{2}'; then
		icon="$ICON_BLUETOOTH"
	else
		icon=$(get_device_icon "$desc")
	fi
	echo "${icon} ${desc}"
}
get_source_display_name() {
	local raw="$1" id="$2"
	local desc
	desc=$(echo "$raw" | sed -e 's/bluez_input\.//; s/alsa_input\.//; s/\.analog-stereo//; s/[[:space:]]+$//')
	local icon
	icon=$(get_device_icon "$desc")
	echo "${icon} ${desc}"
}

# --- Aktif ID’yi bloktan yıldız ile yakala -------------------------------------
__find_active_from_block() {
	sed -E 's/^[[:space:]│└┌┐┘├┤┬┴─]+//' <<<"$1" |
		awk '
      /^\*/ { line=$0; sub(/^\*[[:space:]]*/,"", line);
               if (match(line, /^([0-9]+)/, m)) { print m[1]; exit } }
    '
}

# wpctl inspect üzerinden varsayılan node ID'sini güvenilir şekilde al.
__default_node_id() {
	local token="$1"
	local line
	line="$(wpctl inspect "${token}" 2>/dev/null | head -n1)"
	if [[ "${line}" =~ id[[:space:]]+([0-9]+) ]]; then
		echo "${BASH_REMATCH[1]}"
	fi
}
__node_media_class() {
	local node_id="$1"
	wpctl inspect "${node_id}" 2>/dev/null |
		sed -n -E 's/^[[:space:]]*\*?[[:space:]]*media.class = "(.*)"/\1/p' |
		head -n1
}
__node_name() {
	local node_id="$1"
	wpctl inspect "${node_id}" 2>/dev/null |
		sed -n -E 's/^[[:space:]]*\*?[[:space:]]*node.name = "(.*)"/\1/p' |
		head -n1
}
__node_description() {
	local node_id="$1"
	wpctl inspect "${node_id}" 2>/dev/null |
		sed -n -E 's/^[[:space:]]*\*?[[:space:]]*node.description = "(.*)"/\1/p' |
		head -n1
}
__node_media_name() {
	local node_id="$1"
	wpctl inspect "${node_id}" 2>/dev/null |
		sed -n -E 's/^[[:space:]]*\*?[[:space:]]*media.name = "(.*)"/\1/p' |
		head -n1
}
__pulse_sink_name_from_node_id() {
	local node_id="$1"
	local node_name
	node_name="$(__node_name "${node_id}")"
	[[ -n "${node_name}" ]] || return 1
	command -v pactl >/dev/null 2>&1 || return 1
	pactl list short sinks 2>/dev/null |
		awk -v needle="${node_name}" '$2==needle {print $2; exit}'
}
__sink_active_port_available() {
	local node_id="$1"
	command -v pactl >/dev/null 2>&1 || return 0

	local pulse_sink_name
	pulse_sink_name="$(__pulse_sink_name_from_node_id "${node_id}")"
	[[ -n "${pulse_sink_name}" ]] || return 0

	local sink_block
	sink_block="$(
		pactl list sinks 2>/dev/null | awk -v name="${pulse_sink_name}" '
      BEGIN{capture=0; found=0}
      /^Sink #[0-9]+/ {
        if (capture) exit
      }
      {
        if ($0 ~ /^[[:space:]]*Name:[[:space:]]*/) {
          line=$0
          sub(/^[[:space:]]*Name:[[:space:]]*/, "", line)
          if (line == name) { capture=1; found=1 }
        }
        if (capture) print
      }
      END { if (!found) exit 1 }'
	)" || return 0

	local active_port
	active_port="$(printf "%s\n" "${sink_block}" | sed -n 's/^[[:space:]]*Active Port:[[:space:]]*//p' | head -n1)"
	[[ -z "${active_port}" ]] && return 0

	if printf "%s\n" "${sink_block}" | awk -v ap="${active_port}" '
      BEGIN { found=0 }
      {
        line=$0
        sub(/^[[:space:]]*/, "", line)
        if (index(line, ap ":") == 1) {
          found=1
          if (line ~ /not available\)/) exit 1
          exit 0
        }
      }
      END {
        if (!found) exit 0
      }'; then
		return 0
	fi
	return 1
}

# --- Bluetooth’u öne alma -------------------------------------------------------
__prefer_bluetooth_arrays() {
	local ids_bt=() names_bt=() ids_rest=() names_rest=()
	for i in "${!SINK_IDS[@]}"; do
		if echo "${SINKS[$i]}" | grep -qiE 'bluez|bluetooth'; then
			ids_bt+=("${SINK_IDS[$i]}")
			names_bt+=("${SINKS[$i]}")
		else
			ids_rest+=("${SINK_IDS[$i]}")
			names_rest+=("${SINKS[$i]}")
		fi
	done
	SINK_IDS=("${ids_bt[@]}" "${ids_rest[@]}")
	SINKS=("${names_bt[@]}" "${names_rest[@]}")
}

# --- Sinks ----------------------------------------------------------------------
get_sinks() {
	check_command "wpctl" || exit 1
	SINKS=()
	SINK_IDS=()
	local block
	block="$(wpctl status | sed -n '/Sinks:/,/Sources:/p')"
	local filter_block
	filter_block="$(wpctl status | sed -n '/Filters:/,/Streams:/p')"

	while IFS= read -r line; do
		line="$(echo "$line" | __strip)"
		[[ "$line" =~ ^\*?[[:space:]]*[0-9]+\. ]] || continue
		local id name
		id="$(echo "$line" | sed -E 's/^\*?[[:space:]]*([0-9]+)\..*/\1/')"
		name="$(echo "$line" | sed -E 's/^\*?[[:space:]]*[0-9]+\.\s*//; s/\[vol:.*\]//; s/[[:space:]]+$//')"
		[[ -n "$id" && -n "$name" ]] || continue
		local media_class
		media_class="$(__node_media_class "$id")"
		[[ -n "${media_class}" && "${media_class}" != "Audio/Sink" ]] && continue
		if [[ "${INCLUDE_UNAVAILABLE_SINKS}" != true ]] && ! __sink_active_port_available "${id}"; then
			continue
		fi
		if [[ -n "$EXCLUDE_SINK_REGEX" ]] && echo "$name" | grep -Eq "$EXCLUDE_SINK_REGEX"; then
			continue
		fi
		SINK_IDS+=("$id")
		SINKS+=("$name")
	done <<<"$block"

	# Bazı bluetooth sink'ler "Sinks" yerine "Filters" bloğunda [Audio/Sink] olarak görünür.
	while IFS= read -r line; do
		line="$(echo "$line" | __strip)"
		[[ "$line" =~ ^\*?[[:space:]]*[0-9]+\. ]] || continue
		[[ "$line" =~ \[Audio/Sink\] ]] || continue
		local id name media_class
		id="$(echo "$line" | sed -E 's/^\*?[[:space:]]*([0-9]+)\..*/\1/')"
		name="$(echo "$line" | sed -E 's/^\*?[[:space:]]*[0-9]+\.\s*//; s/\s*\[Audio\/Sink\]\s*$//; s/[[:space:]]+$//')"
		[[ -n "$id" && -n "$name" ]] || continue
		id_in_array "$id" "${SINK_IDS[@]}" && continue
		media_class="$(__node_media_class "$id")"
		[[ -n "${media_class}" && "${media_class}" != "Audio/Sink" ]] && continue
		if [[ "${INCLUDE_UNAVAILABLE_SINKS}" != true ]] && ! __sink_active_port_available "${id}"; then
			continue
		fi
		if [[ -n "$EXCLUDE_SINK_REGEX" ]] && echo "$name" | grep -Eq "$EXCLUDE_SINK_REGEX"; then
			continue
		fi
		SINK_IDS+=("$id")
		SINKS+=("$name")
	done <<<"$filter_block"

	if [ "${PREFER_BLUETOOTH}" = true ] && (printf "%s\n" "${SINKS[@]}" | grep -qiE 'bluez|bluetooth'); then
		__prefer_bluetooth_arrays
	fi

	SINKS_COUNT=${#SINKS[@]}
	local active_id
	active_id="$(__find_active_from_block "$block")"
	[[ -z "${active_id}" ]] && active_id="$(__default_node_id @DEFAULT_AUDIO_SINK@)"
	RUNNING_SINK=""
	SINK_INDEX=-1
	for i in "${!SINK_IDS[@]}"; do
		if [[ "${SINK_IDS[$i]}" == "$active_id" ]]; then
			SINK_INDEX=$i
			RUNNING_SINK="${SINKS[$i]}"
			break
		fi
	done

	$DEBUG && {
		echo "${BLUE}-- SINKS --${RESET}"
		for i in "${!SINK_IDS[@]}"; do
			local mark=""
			[[ $i -eq $SINK_INDEX ]] && mark=" ${GREEN}[aktif]${RESET}"
			echo "  $i: ID=${SINK_IDS[$i]}  ${SINKS[$i]}$mark"
		done
	}
}

# --- Sources --------------------------------------------------------------------
get_sources() {
	check_command "wpctl" || exit 1
	SOURCES=()
	SOURCE_IDS=()
	local block
	block="$(wpctl status | sed -n '/Sources:/,/Filters:/p')"

	while IFS= read -r line; do
		line="$(echo "$line" | __strip)"
		[[ "$line" =~ ^\*?[[:space:]]*[0-9]+\. ]] || continue
		local id name
		id="$(echo "$line" | sed -E 's/^\*?[[:space:]]*([0-9]+)\..*/\1/')"
		name="$(echo "$line" | sed -E 's/^\*?[[:space:]]*[0-9]+\.\s*//; s/\[vol:.*\]//; s/[[:space:]]+$//')"
		[[ "$name" =~ [Mm]onitor ]] && continue
		[[ -n "$id" && -n "$name" ]] || continue
		SOURCE_IDS+=("$id")
		SOURCES+=("$name")
	done <<<"$block"

	SOURCES_COUNT=${#SOURCES[@]}
	local active_id
	active_id="$(__find_active_from_block "$block")"
	[[ -z "${active_id}" ]] && active_id="$(__default_node_id @DEFAULT_AUDIO_SOURCE@)"
	DEFAULT_SOURCE=""
	SOURCE_INDEX=-1
	for i in "${!SOURCE_IDS[@]}"; do
		if [[ "${SOURCE_IDS[$i]}" == "$active_id" ]]; then
			SOURCE_INDEX=$i
			DEFAULT_SOURCE="${SOURCES[$i]}"
			break
		fi
	done

	$DEBUG && {
		echo "${BLUE}-- SOURCES --${RESET}"
		for i in "${!SOURCE_IDS[@]}"; do
			local mark=""
			[[ $i -eq $SOURCE_INDEX ]] && mark=" ${GREEN}[aktif]${RESET}"
			echo "  $i: ID=${SOURCE_IDS[$i]}  ${SOURCES[$i]}$mark"
		done
	}
}

# --- Gerçek yüzde okumaları -----------------------------------------------------
__percent_from_wpctl() {
	local line
	line="$(wpctl get-volume "$1" 2>/dev/null | head -n1)"
	if [[ "$line" =~ ([0-9]+\.[0-9]+) ]]; then
		awk -v v="${BASH_REMATCH[1]}" 'BEGIN{printf("%d", v*100 + 0.5)}'
	else
		echo ""
	fi
}
notify_volume() {
	local vol
	vol="$(__percent_from_wpctl @DEFAULT_AUDIO_SINK@)"
	[ -z "$vol" ] && vol="${DEFAULT_VOLUME}"
	local icon="audio-volume-high"
	if ((vol == 0)); then
		icon="audio-volume-muted"
	elif ((vol < 30)); then
		icon="audio-volume-low"
	elif ((vol < 70)); then
		icon="audio-volume-medium"
	fi
	notify "Ses Seviyesi" "Ses: ${vol}%" "$icon"
}
notify_mic() {
	local vol
	vol="$(__percent_from_wpctl @DEFAULT_AUDIO_SOURCE@)"
	[ -z "$vol" ] && vol="${DEFAULT_MIC_VOLUME}"
	notify "Mikrofon Seviyesi" "Mikrofon: ${vol}%" "audio-input-microphone"
}
notify_mute() { notify "Ses" "Ses durumu değiştirildi" "audio-volume-muted"; }
__mic_is_muted() {
	wpctl get-volume @DEFAULT_AUDIO_SOURCE@ 2>/dev/null | grep -q "MUTED"
}
__volume_bar() {
	local vol="$1"
	local bar_length=10
	local filled=$((vol * bar_length / 100))
	local empty=$((bar_length - filled))
	printf "["
	printf "█%.0s" $(seq 1 $filled)
	printf "░%.0s" $(seq 1 $empty)
	printf "]"
}
__set_micmute_led() {
	local val="$1"
	local led_path="${MICMUTE_LED_PATH:-/sys/class/leds/platform::micmute/brightness}"
	if [[ -w "$led_path" ]]; then
		echo "$val" >"$led_path" 2>/dev/null || true
	elif command -v sudo >/dev/null 2>&1; then
		echo "$val" | sudo -n tee "$led_path" >/dev/null 2>&1 || true
	fi
}
notify_mic_mute() {
	local vol
	vol="$(__percent_from_wpctl @DEFAULT_AUDIO_SOURCE@)"
	[ -z "$vol" ] && vol="${DEFAULT_MIC_VOLUME}"

	if __mic_is_muted; then
		__set_micmute_led 1
		notify "Mikrofon" "Kapalı" "microphone-sensitivity-muted"
	else
		__set_micmute_led 0
		notify "Mikrofon" "Açık: ${vol}% $(__volume_bar "$vol")" "audio-input-microphone"
	fi
}

# --- Streams’leri yeni varsayılan sink’e taşı ----------------------------------
migrate_streams_to_sink() {
	local target_sink_id="$1"
	[[ -n "${target_sink_id}" ]] || return 0

	local pulse_sink_name
	pulse_sink_name="$(__pulse_sink_name_from_node_id "${target_sink_id}")"
	if [[ -n "${pulse_sink_name}" ]]; then
		while read -r stream_id _; do
			[[ "${stream_id}" =~ ^[0-9]+$ ]] || continue
			pactl move-sink-input "${stream_id}" "${pulse_sink_name}" >/dev/null 2>&1 || true
		done < <(pactl list short sink-inputs 2>/dev/null)
		return 0
	fi

	wpctl --help 2>/dev/null | grep -q 'move-node' || return 0

	local streams
	streams="$(
		wpctl status | awk '
      BEGIN{in_streams=0}
      /^[[:space:]]*└─ Streams:/ {in_streams=1; next}
      in_streams {
        if ($0 ~ /^[[:space:]]*[A-Za-z][A-Za-z[:space:]]*$/) exit
        line=$0
        if (line ~ /[><]/) next
        gsub(/^[[:space:]│└┌┐┘├┤┬┴─*]+/, "", line)
        if (match(line, /^([0-9]+)\./, m)) print m[1]
      }'
	)"
	while IFS= read -r sid; do
		[[ -n "$sid" ]] || continue
		wpctl inspect "$sid" 2>/dev/null | grep -q 'media.class = "Stream/Output/Audio"' || continue
		wpctl move-node "$sid" "${target_sink_id}" >/dev/null 2>&1 || true
	done <<<"$streams"
}

# --- Operasyonlar ---------------------------------------------------------------
switch_sink() {
	local target_sink_id="$1"
	if ! wpctl set-default "${target_sink_id}"; then
		error "Failed to set default sink: ${target_sink_id}"
		return 1
	fi
	local pulse_sink_name
	pulse_sink_name="$(__pulse_sink_name_from_node_id "${target_sink_id}")"
	if [[ -n "${pulse_sink_name}" ]]; then
		pactl set-default-sink "${pulse_sink_name}" >/dev/null 2>&1 || true
	fi

	# WirePlumber güncellemesini bekle ve gerekirse bir kez daha zorla.
	sleep 0.05
	local confirmed_sink_id
	confirmed_sink_id="$(__default_node_id @DEFAULT_AUDIO_SINK@)"
	if [[ -n "${confirmed_sink_id}" && "${confirmed_sink_id}" != "${target_sink_id}" ]]; then
		wpctl set-default "${target_sink_id}" >/dev/null 2>&1 || true
		sleep 0.05
	fi

	migrate_streams_to_sink "${target_sink_id}"
	save_state "last_sink" "${target_sink_id}"

	get_sinks
	local display="ID ${target_sink_id}"
	for i in "${!SINK_IDS[@]}"; do
		if [[ "${SINK_IDS[$i]}" == "${target_sink_id}" ]]; then
			display=$(get_sink_display_name "${SINKS[$i]}" "${target_sink_id}")
			break
		fi
	done
	notify "Ses Çıkışı Değiştirildi" "${display}" "audio-card"
	return 0
}
switch_source() {
	local target_source_id="$1"
	if ! wpctl set-default "${target_source_id}"; then
		error "Failed to set default source: ${target_source_id}"
		return 1
	fi
	save_state "last_source" "${target_source_id}"

	get_sources
	local display="ID ${target_source_id}"
	for i in "${!SOURCE_IDS[@]}"; do
		if [[ "${SOURCE_IDS[$i]}" == "${target_source_id}" ]]; then
			display=$(get_source_display_name "${SOURCES[$i]}" "${target_source_id}")
			break
		fi
	done
	notify "Mikrofon Değiştirildi" "${display}" "audio-input-microphone"
	return 0
}
switch_to_sink_index() {
	local index="$1"
	if ((index >= 0 && index < ${#SINK_IDS[@]})); then
		local id="${SINK_IDS[$index]}"
		debug_print "Sink Değiştirme" "Index ${index} -> ID ${id} (${SINKS[$index]})"
		switch_sink "${id}"
	else
		error "Invalid sink index: ${index} (0..$((${#SINK_IDS[@]} - 1)))"
		return 1
	fi
}
switch_to_source_index() {
	local index="$1"
	if ((index >= 0 && index < ${#SOURCE_IDS[@]})); then
		local id="${SOURCE_IDS[$index]}"
		debug_print "Source Değiştirme" "Index ${index} -> ID ${id} (${SOURCES[$index]})"
		switch_source "${id}"
	else
		error "Invalid source index: ${index} (0..$((${#SOURCE_IDS[@]} - 1)))"
		return 1
	fi
}
handle_switch() {
	get_sinks
	if ((SINKS_COUNT == 0)); then
		error "No eligible audio outputs (all excluded by EXCLUDE_SINK_REGEX?)."
		notify "Hata" "Uygun ses çıkışı yok (EXCLUDE_SINK_REGEX çok kısıtlayıcı olabilir)." "dialog-error"
		return 1
	fi
	if ((SINKS_COUNT == 1)); then
		notify "Bilgi" "Sadece bir uygun ses cihazı mevcut" "dialog-information"
		return 0
	fi
	local base_index="${SINK_INDEX}"
	local last_sink last_index=-1
	last_sink="$(load_state "last_sink")"
	if [[ -n "${last_sink}" && "${last_sink}" =~ ^[0-9]+$ ]]; then
		for i in "${!SINK_IDS[@]}"; do
			if [[ "${SINK_IDS[$i]}" == "${last_sink}" ]]; then
				last_index="$i"
				break
			fi
		done
	fi

	if ((last_index >= 0)); then
		local active_id=""
		((base_index >= 0)) && active_id="${SINK_IDS[$base_index]}"
		if [[ "${active_id}" != "${last_sink}" ]]; then
			base_index="${last_index}"
			debug_print "Switch Fallback" "Aktif sink tespiti güvenilir değil; last_sink (${last_sink}) baz alındı."
		fi
	fi

	local next_index
	if ((base_index < 0)); then
		next_index=0
		debug_print "İlk Cihaz" "Aktif mevcut listede değil, 0'a geçiliyor"
	else
		next_index=$(((base_index + 1) % SINKS_COUNT))
	fi
	switch_to_sink_index "${next_index}"
}
handle_switch_mic() {
	get_sources
	if ((SOURCES_COUNT == 0)); then
		error "No microphones found."
		notify "Hata" "Mikrofon bulunamadı." "dialog-error"
		return 1
	fi
	local next_index
	if ((SOURCE_INDEX < 0)); then
		next_index=0
	else
		next_index=$(((SOURCE_INDEX + 1) % SOURCES_COUNT))
	fi
	switch_to_source_index "${next_index}"
}

# --- Ses/Mic seviye kontrolü ---------------------------------------------------
control_volume() {
	check_command "wpctl" || exit 1
	case "$1" in
	up)
		wpctl set-volume @DEFAULT_AUDIO_SINK@ ${VOLUME_STEP}%+
		notify_volume
		;;
	down)
		wpctl set-volume @DEFAULT_AUDIO_SINK@ ${VOLUME_STEP}%-
		notify_volume
		;;
	set)
		if [[ "$2" =~ ^[0-9]+$ ]] && [ "$2" -le 100 ]; then
			wpctl set-volume @DEFAULT_AUDIO_SINK@ ${2}%
			notify_volume
		else error "Invalid volume level (0-100)"; fi
		;;
	mute)
		wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle
		notify_mute
		;;
	*)
		error "Unknown volume subcommand"
		return 1
		;;
	esac
}
control_mic() {
	check_command "wpctl" || exit 1
	case "$1" in
	up)
		wpctl set-volume @DEFAULT_AUDIO_SOURCE@ ${VOLUME_STEP}%+
		notify_mic
		;;
	down)
		wpctl set-volume @DEFAULT_AUDIO_SOURCE@ ${VOLUME_STEP}%-
		notify_mic
		;;
	set)
		if [[ "$2" =~ ^[0-9]+$ ]] && [ "$2" -le 100 ]; then
			wpctl set-volume @DEFAULT_AUDIO_SOURCE@ ${2}%
			notify_mic
		else error "Invalid microphone level (0-100)"; fi
		;;
	mute)
		wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle
		notify_mic_mute
		;;
	*)
		error "Unknown mic subcommand"
		return 1
		;;
	esac
}

# --- Init / Profiller / Liste ---------------------------------------------------
initialize_audio() {
	check_command "wpctl" || exit 1
	info "Initializing audio levels..."
	wpctl set-volume @DEFAULT_AUDIO_SINK@ ${DEFAULT_VOLUME}% >/dev/null 2>&1 || true
	wpctl set-volume @DEFAULT_AUDIO_SOURCE@ ${DEFAULT_MIC_VOLUME}% >/dev/null 2>&1 || true

	get_sinks
	get_sources
	if [ "${SAVE_PREFERENCES}" = true ] && [ -f "${STATE_FILE}" ]; then
		local last_sink last_source
		last_sink="$(load_state "last_sink")"
		last_source="$(load_state "last_source")"
		if [[ -n "${last_sink}" && "${last_sink}" =~ ^[0-9]+$ ]] && id_in_array "${last_sink}" "${SINK_IDS[@]}"; then
			wpctl set-default "${last_sink}" >/dev/null 2>&1 || debug_print "Uyarı" "Sink ayarlanamadı: ${last_sink}"
		fi
		if [[ -n "${last_source}" && "${last_source}" =~ ^[0-9]+$ ]] && id_in_array "${last_source}" "${SOURCE_IDS[@]}"; then
			wpctl set-default "${last_source}" >/dev/null 2>&1 || debug_print "Uyarı" "Source ayarlanamadı: ${last_source}"
		fi
	fi
	notify "Ses Ayarları" "Ses: %${DEFAULT_VOLUME}, Mikrofon: %${DEFAULT_MIC_VOLUME}" "audio-volume-medium"
	success "Audio initialized successfully"
}
save_profile() {
	local name="${1:-default}"
	local file="${PROFILES_DIR}/${name}.profile"
	info "Saving profile: ${name}"
	get_sinks
	get_sources
	local cur_sink=""
	local cur_source=""
	((SINK_INDEX >= 0)) && cur_sink="${SINK_IDS[$SINK_INDEX]}"
	((SOURCE_INDEX >= 0)) && cur_source="${SOURCE_IDS[$SOURCE_INDEX]}"
	local sink_vol
	sink_vol="$(__percent_from_wpctl @DEFAULT_AUDIO_SINK@)"
	local src_vol
	src_vol="$(__percent_from_wpctl @DEFAULT_AUDIO_SOURCE@)"
	[ -z "${sink_vol}" ] && sink_vol="${DEFAULT_VOLUME}"
	[ -z "${src_vol}" ] && src_vol="${DEFAULT_MIC_VOLUME}"
	cat >"${file}" <<EOF
# Audio Profile: ${name}
# Created: $(date)
PROFILE_SINK="${cur_sink}"
PROFILE_SOURCE="${cur_source}"
PROFILE_SINK_VOLUME="${sink_vol}"
PROFILE_SOURCE_VOLUME="${src_vol}"
EOF
	notify "Profile Saved" "${name}" "document-save"
	success "Profile '${name}' saved successfully"
}
load_profile() {
	local name="${1:-default}"
	local file="${PROFILES_DIR}/${name}.profile"
	if [ ! -f "${file}" ]; then
		error "Profile not found: ${name}"
		return 1
	fi
	# shellcheck disable=SC1090
	source "${file}"
	[ -n "${PROFILE_SINK}" ] && wpctl set-default "${PROFILE_SINK}" >/dev/null 2>&1 || true
	[ -n "${PROFILE_SOURCE}" ] && wpctl set-default "${PROFILE_SOURCE}" >/dev/null 2>&1 || true
	[ -n "${PROFILE_SINK_VOLUME}" ] && wpctl set-volume @DEFAULT_AUDIO_SINK@ "${PROFILE_SINK_VOLUME}%" >/dev/null 2>&1 || true
	[ -n "${PROFILE_SOURCE_VOLUME}" ] && wpctl set-volume @DEFAULT_AUDIO_SOURCE@ "${PROFILE_SOURCE_VOLUME}%" >/dev/null 2>&1 || true
	notify "Profile Loaded" "${name}" "document-open"
	success "Profile '${name}' loaded successfully"
}
list_profiles() {
	info "Available profiles:"
	if [ -z "$(ls -A "${PROFILES_DIR}" 2>/dev/null)" ]; then
		echo "  No profiles found"
		return
	fi
	for profile in "${PROFILES_DIR}"/*.profile; do
		[ -f "${profile}" ] || continue
		local name
		name="$(basename "${profile}" .profile)"
		local created
		created="$(grep "^# Created:" "${profile}" | cut -d: -f2-)"
		echo "  ${GREEN}${name}${RESET} - Created:${created}"
	done
}
list_devices() {
	echo "${BOLD}Ses Çıkışları (filtre sonrası):${RESET}"
	echo "─────────────────────────"
	get_sinks
	for i in "${!SINKS[@]}"; do
		local disp
		disp="$(get_sink_display_name "${SINKS[$i]}" "${SINK_IDS[$i]}")"
		local mark=""
		[[ $i -eq $SINK_INDEX ]] && mark=" ${GREEN}[aktif]${RESET}"
		echo "$i: ${disp}${mark}"
	done
	echo
	echo "${BOLD}Mikrofonlar:${RESET}"
	echo "─────────────────────────"
	get_sources
	for i in "${!SOURCES[@]}"; do
		local disp
		disp="$(get_source_display_name "${SOURCES[$i]}" "${SOURCE_IDS[$i]}")"
		local mark=""
		[[ $i -eq $SOURCE_INDEX ]] && mark=" ${GREEN}[aktif]${RESET}"
		echo "$i: ${disp}${mark}"
	done
}

# --- CLI -----------------------------------------------------------------------
print_help() {
	cat <<EOF
${BOLD}HyprFlow PipeWire Audio Switcher v${VERSION}${RESET}

Kullanım:
  $0 [-d|--debug] [--help] [--version] <komut> [parametreler]

Komutlar:
  ${CYAN}Ses Çıkışı:${RESET}
    switch               Sonraki uygun ses çıkışına geç (EXCLUDE_SINK_REGEX'e göre)
    switch-interactive   İnteraktif ses çıkışı seçimi (fzf)

  ${CYAN}Mikrofon:${RESET}
    switch-mic           Sonraki mikrofona geç
    mic-interactive      İnteraktif mikrofon seçimi (fzf)

  ${CYAN}Ses Kontrolü:${RESET}
    volume up|down|set N|mute
    mic    up|down|set N|mute

  ${CYAN}Profiller:${RESET}
    save-profile [isim]  Profili kaydet
    load-profile [isim]  Profili yükle
    list-profiles        Profilleri listele

  ${CYAN}Diğer:${RESET}
    init                 Varsayılan ses seviyelerini uygula + tercihler
    list                 Cihazları listele (filtre sonrası)
    version              Sürüm bilgisini göster
    help                 Bu yardım

Kalıcı klasör: ${CACHE_DIR}
Profiller:      ${PROFILES_DIR}/

ENV override örnekleri:
  EXCLUDE_SINK_REGEX="HDMI|DisplayPort"  PREFER_BLUETOOTH=true  DEBUG=true
EOF
}
print_version() {
	echo "${BOLD}HyprFlow PipeWire Audio Switcher${RESET}"
	echo "Version: ${VERSION}"
	echo "Cache:   ${CACHE_DIR}"
	echo "Profiles:${PROFILES_DIR}"
}

main() {
	# set -e YOK; bilinçli. Kullanıcı isteği: daha toleranslı çalışsın.
	check_dependencies
	$SHOW_VERSION && {
		print_version
		exit 0
	}
	$SHOW_HELP && {
		print_help
		exit 0
	}

	case "$1" in
	volume)
		shift
		control_volume "$@"
		;;
	mic)
		shift
		control_mic "$@"
		;;
	switch) handle_switch ;;
	switch-interactive) select_sink_interactive ;;
	switch-mic) handle_switch_mic ;;
	mic-interactive) select_source_interactive ;;
	init) initialize_audio ;;
	save-profile)
		shift
		save_profile "$1"
		;;
	load-profile)
		shift
		load_profile "$1"
		;;
	list-profiles) list_profiles ;;
	version) print_version ;;
	list) list_devices ;;
	help | "") print_help ;;
	*) print_help ;;
	esac
}

main "$@"
