#!/usr/bin/env bash
# ==============================================================================
# Script: osc-stream.sh
# Description: Unified stream player for margo (radio / vradio / tv / lofi)
# Usage: osc-stream <subcommand> [args]   (no subcommand => radio)
#
# Subcommands:
#   radio [args]   Interactive internet-radio player via mpv/cvlc (the engine).
#                  Flags: -t N (toggle station N), -s (stop), -l (list),
#                         -p (switch player), -h (help), N (play station N).
#                  This is the DEFAULT when no subcommand is given.
#   vradio         Preset launcher: stop any running stream then play station 1.
#   tv [args]      IPTV channel splitter/player for iptv-org streams.
#   lofi           Toggle a YouTube lo-fi radio stream (mpv + yt-dlp).
#   help           Show this help.
#
# Merged from: osc-radio.sh, osc-vradio.sh, osc-tv-splitter.sh, lofi.sh
# Author: Kenan Pelit | License: MIT
# ==============================================================================

# Disable debug output
set +x

# ------------------------------------------------------------------------------
# Shared helpers (colors / logging / notify / dependency checks / mpv launch)
# ------------------------------------------------------------------------------

# Color definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color
BOLD='\033[1m'

# Dependency check primitive
have() { command -v "$1" >/dev/null 2>&1; }

# Desktop notification (no-op if notify-send is unavailable)
notify() {
	local title=$1 message=$2
	have notify-send && notify-send -i "audio-x-generic" "$title" "$message" -t 2000
}

# Logging helpers (used mainly by the tv subcommand)
error() {
	echo -e "${RED}ERROR: $1${NC}" >&2
	exit 1
}

success() {
	echo -e "${GREEN}✓ $1${NC}"
}

info() {
	echo -e "${YELLOW}→ $1${NC}"
}

# Background mpv launcher (prefers runbg if present, falls back to plain bg)
mpv_play() {
	if have runbg; then
		runbg mpv "$@"
	else
		mpv "$@" &
	fi
}

# ==============================================================================
# RADIO ENGINE (ported from osc-radio.sh) -- tradio, Terminal Based Radio Player
# ==============================================================================

# Radio stations - Virgin Radio first, rest alphabetically sorted
declare -A RADIOS
RADIOS=(
	["Virgin Radio"]="http://playerservices.streamtheworld.com/api/livestream-redirect/VIRGIN_RADIO_SC"
	["Joy FM"]="http://playerservices.streamtheworld.com/api/livestream-redirect/JOY_FM_SC"
	["Joy Jazz"]="http://playerservices.streamtheworld.com/api/livestream-redirect/JOY_JAZZ_SC"
	["Kral 45lik"]="https://ssldyg.radyotvonline.com/kralweb/smil:kral45lik.smil/chunklist_w1544647566_b64000.m3u8"
	["Metro FM"]="http://playerservices.streamtheworld.com/api/livestream-redirect/METRO_FM_SC"
	["NTV Radyo"]="http://ntvrdsc.radyotvonline.com/"
	["Pal Akustik"]="http://shoutcast.radyogrup.com:2030/"
	["Pal Dance"]="http://shoutcast.radyogrup.com:2040/"
	["Pal Nostalji"]="http://shoutcast.radyogrup.com:1010/"
	["Pal Orient"]="http://shoutcast.radyogrup.com:1050/"
	["Pal Slow"]="http://shoutcast.radyogrup.com:2020/"
	["Pal Station"]="http://shoutcast.radyogrup.com:1020/"
	["Radyo 45lik"]="http://104.236.16.158:3060/"
	["Radyo Dejavu"]="http://radyodejavu.canliyayinda.com:8054/"
	["Radyo Voyage"]="http://voyagewmp.radyotvonline.com:80/"
	["Retro Türk"]="http://playerservices.streamtheworld.com/api/livestream-redirect/RETROTURK_SC"
	["World Hits"]="http://37.247.98.8/stream/34/.mp3"
)

# Configuration files
CONFIG_DIR="$HOME/.config/tradio"
CONFIG_FILE="$CONFIG_DIR/config"
HISTORY_FILE="$CONFIG_DIR/history"
FAVORITES_FILE="$CONFIG_DIR/favorites"
PID_FILE="/tmp/tradio_player.pid"
NOW_PLAYING_FILE="/tmp/tradio_current.txt"

# Default volume
VOLUME=100

# Default player (can be 'cvlc' or 'mpv')
PLAYER="cvlc"

# Dependency check with generic instructions
check_dependencies() {
	local deps=("$PLAYER" "mpv")
	local missing=()

	for dep in "${deps[@]}"; do
		if ! have "$dep"; then
			missing+=("$dep")
		fi
	done

	if [ ${#missing[@]} -ne 0 ]; then
		echo -e "${RED}Missing dependencies: ${missing[*]}${NC}"
		echo "Please install the following packages using your system's package manager:"
		for dep in "${missing[@]}"; do
			echo "- $dep"
		done
		exit 1
	fi
}

# Configuration management
init_config() {
	mkdir -p "$CONFIG_DIR"
	[ ! -f "$CONFIG_FILE" ] && echo "volume=$VOLUME" >"$CONFIG_FILE"
	[ ! -f "$HISTORY_FILE" ] && touch "$HISTORY_FILE"
	[ ! -f "$FAVORITES_FILE" ] && touch "$FAVORITES_FILE"

	# Read configuration
	source "$CONFIG_FILE"
}

# Create the ordered station list
create_station_list() {
	# First, include Virgin Radio
	SORTED_STATIONS=("Virgin Radio")

	# Then add all other stations alphabetically
	local temp_stations=()
	for station in "${!RADIOS[@]}"; do
		if [ "$station" != "Virgin Radio" ]; then
			temp_stations+=("$station")
		fi
	done

	# Sort the temporary array
	IFS=$'\n' sorted=($(sort <<<"${temp_stations[*]}"))
	unset IFS

	# Combine arrays
	SORTED_STATIONS+=("${sorted[@]}")
}

# History management
add_to_history() {
	local name=$1
	echo "$(date '+%Y-%m-%d %H:%M:%S') - $name" >>"$HISTORY_FILE"
}

# Favorites management
add_to_favorites() {
	local name=$1
	if ! grep -q "^$name$" "$FAVORITES_FILE"; then
		echo "$name" >>"$FAVORITES_FILE"
		echo -e "${GREEN}Added $name to favorites${NC}"
	fi
}

remove_from_favorites() {
	local name=$1
	sed -i "/^$name$/d" "$FAVORITES_FILE"
	echo -e "${YELLOW}Removed $name from favorites${NC}"
}

# Function to check if radio is playing
is_radio_playing() {
	if [ -f "$PID_FILE" ]; then
		local pid
		pid=$(cat "$PID_FILE")
		if ps -p "$pid" >/dev/null 2>&1; then
			return 0 # Radio is playing
		fi
	fi
	return 1 # Radio is not playing
}

# Function to stop playing radio
stop_radio() {
	if [ -f "$PID_FILE" ]; then
		local pid
		pid=$(cat "$PID_FILE")
		if ps -p "$pid" >/dev/null 2>&1; then
			echo -e "${YELLOW}Stopping radio...${NC}"
			kill "$pid" >/dev/null 2>&1
			rm -f "$PID_FILE"
			rm -f "$NOW_PLAYING_FILE"
		fi
	fi
}

# Volume control for various environments
change_volume() {
	local new_vol=$1
	VOLUME=$new_vol
	sed -i "s/volume=.*/volume=$VOLUME/" "$CONFIG_FILE"

	# Try different volume control methods
	if have pactl; then
		pactl set-sink-volume @DEFAULT_SINK@ "${VOLUME}%"
	elif have amixer; then
		amixer -q sset Master "${VOLUME}%" 2>/dev/null
	fi
}

# Enhanced radio playback function with PID tracking
play_radio() {
	local url=$1
	local name=$2
	local toggle=$3
	local play_status=0

	# Validate input parameters
	if [[ -z "$url" || -z "$name" ]]; then
		echo -e "${RED}Error: Missing required parameters${NC}"
		return 1
	fi

	# Handle toggle logic
	if [[ "$toggle" = "true" && -f "$NOW_PLAYING_FILE" ]]; then
		local current_station
		current_station=$(cat "$NOW_PLAYING_FILE" 2>/dev/null)

		if [[ -n "$current_station" && "$current_station" = "$name" ]]; then
			stop_radio
			return 0
		elif is_radio_playing; then
			stop_radio
		fi
	fi

	# Notification and history
	echo -e "${GREEN}Starting: $name${NC}"
	notify "🎵 Radio Player" "Now playing: $name"
	add_to_history "$name"

	# Start player based on selected player
	if [[ "$PLAYER" == "cvlc" ]]; then
		cvlc --no-video \
			--play-and-exit \
			--quiet \
			--intf dummy \
			--volume="$VOLUME" \
			"$url" 2>/dev/null &
		play_status=$?
	elif [[ "$PLAYER" == "mpv" ]]; then
		mpv --no-video \
			--quiet \
			--volume="$VOLUME" \
			"$url" 2>/dev/null &
		play_status=$?
	else
		echo -e "${RED}Unsupported player: $PLAYER${NC}"
		return 1
	fi

	# Handle player start status
	if [[ $play_status -eq 0 ]]; then
		# Save PID and current station
		echo $! >"$PID_FILE"
		echo "$name" >"$NOW_PLAYING_FILE"
		chmod 600 "$PID_FILE" "$NOW_PLAYING_FILE"

		# Verify player is actually running
		sleep 1
		if ! is_radio_playing; then
			rm -f "$PID_FILE" "$NOW_PLAYING_FILE"
			echo -e "${RED}Failed to start playback${NC}"
			return 1
		fi
		return 0
	else
		rm -f "$PID_FILE" "$NOW_PLAYING_FILE"
		echo -e "${RED}Failed to start player${NC}"
		return 1
	fi
}

# Function to play station by number
play_station_by_number() {
	local number=$1
	local toggle=$2

	if [ "$number" -gt 0 ] && [ "$number" -le ${#SORTED_STATIONS[@]} ]; then
		local station_name="${SORTED_STATIONS[$((number - 1))]}"
		play_radio "${RADIOS[$station_name]}" "$station_name" "$toggle"

		# Clear and show minimal info
		clear
		echo -e "${BOLD}🎵 Terminal Radio Player v1.1${NC}"
		echo "----------------------------------------"
		echo -e "Volume: $VOLUME%"
		echo -e "Now Playing: $station_name"
		echo -e "Player: $PLAYER"
		echo "----------------------------------------"

		exit 0
	else
		echo -e "${RED}Invalid station number: $number${NC}"
		echo "Available stations: 1-${#SORTED_STATIONS[@]}"
		exit 1
	fi
}

# Search function
search_radio() {
	local search_term=$1
	local matches=()

	for name in "${!RADIOS[@]}"; do
		if [[ ${name,,} =~ ${search_term,,} ]]; then
			matches+=("$name")
		fi
	done

	if [ ${#matches[@]} -eq 0 ]; then
		echo -e "${RED}No results found${NC}"
		return
	fi

	echo -e "${GREEN}Found stations:${NC}"
	local i=1
	for match in "${matches[@]}"; do
		echo -e "${BLUE}$i)${NC} $match"
		((i++))
	done

	echo -e "\nSelect station to play (0 to cancel): "
	read -r choice

	if [ "$choice" -gt 0 ] && [ "$choice" -le ${#matches[@]} ]; then
		play_radio "${RADIOS[${matches[$((choice - 1))]}]}" "${matches[$((choice - 1))]}"
	fi
}

# Improved menu display with better formatting
show_menu() {
	clear
	echo -e "${BOLD}🎵 Terminal Radio Player v1.1${NC}"
	echo "----------------------------------------"
	echo -e "${YELLOW}Volume: $VOLUME%${NC}"
	echo -e "${YELLOW}Player: $PLAYER${NC}"

	# Show current playback status
	if is_radio_playing && [ -f "$NOW_PLAYING_FILE" ]; then
		local current_station
		current_station=$(cat "$NOW_PLAYING_FILE" 2>/dev/null)
		echo -e "${GREEN}Now Playing: $current_station${NC}"
	else
		echo -e "${YELLOW}No station playing${NC}"
	fi
	echo "----------------------------------------"
	echo -e "${BLUE}Available Radio Stations:${NC}"
	echo "----------------------------------------"

	# Calculate the maximum station name length
	local max_length=0
	for name in "${!RADIOS[@]}"; do
		local name_length=${#name}
		[ "$name_length" -gt "$max_length" ] && max_length=$name_length
	done

	# Add padding for proper alignment
	local padding=$((max_length + 5))
	local columns=2 # Reduced columns for better readability
	local i=1
	local col=1

	# Display stations based on sorted array
	for name in "${SORTED_STATIONS[@]}"; do
		local number_pad=""
		[ $i -lt 10 ] && number_pad=" "

		# Add star for favorites
		local star=""
		grep -q "^$name$" "$FAVORITES_FILE" && star="★ "

		printf "(%s%d) %-${padding}s %s" "$number_pad" "$i" "$name" "$star"

		if [ $col -eq $columns ]; then
			echo ""
			col=1
		else
			col=$((col + 1))
			printf "    "
		fi
		((i++))
	done

	# Complete the last line if necessary
	[ $col -ne 1 ] && echo ""

	echo -e "\n${BLUE}Commands:${NC}"
	echo -e "r) Random Play    s) Search"
	echo -e "f) Favorites      h) History"
	echo -e "v) Volume         p) Toggle Player (cvlc/mpv)"
	echo -e "q) Quit"
	echo -e "\nYour choice: "
}

# Cleanup function (radio)
cleanup() {
	stop_radio
	echo -e "\n${GREEN}Exiting...${NC}"
	exit 0
}

# Radio engine main with argument handling (was osc-radio.sh main())
radio_main() {
	# Set up exit trap (scoped to the interactive radio engine)
	trap cleanup INT TERM

	check_dependencies
	init_config
	create_station_list

	# Handle command line arguments
	if [ $# -gt 0 ]; then
		case $1 in
		-h | --help)
			echo "Usage: osc-stream radio [OPTION] [NUMBER]"
			echo "Options:"
			echo "  -h, --help     Show this help"
			echo "  -t, --toggle   Toggle play/stop for given station"
			echo "  -s, --stop     Stop currently playing station"
			echo "  -l, --list     List all available stations"
			echo "  -p, --player   Switch player (cvlc/mpv)"
			echo "  NUMBER         Play station number (1-${#SORTED_STATIONS[@]})"
			exit 0
			;;
		-t | --toggle)
			if [ $# -eq 2 ]; then
				play_station_by_number "$2" "true"
			else
				echo -e "${RED}Error: Station number required for toggle${NC}"
				exit 1
			fi
			;;
		-s | --stop)
			stop_radio
			exit 0
			;;
		-l | --list)
			echo -e "${BLUE}Available Radio Stations:${NC}"
			local i=1
			for station in "${SORTED_STATIONS[@]}"; do
				echo "$i) $station"
				((i++))
			done
			exit 0
			;;
		-p | --player)
			# Toggle between VLC and MPV
			if [[ "$PLAYER" == "cvlc" ]]; then
				PLAYER="mpv"
				echo -e "${GREEN}Switched to MPV player${NC}"
			else
				PLAYER="cvlc"
				echo -e "${GREEN}Switched to VLC player${NC}"
			fi
			exit 0
			;;
		*)
			if [[ $1 =~ ^[0-9]+$ ]]; then
				play_station_by_number "$1" "false"
			else
				echo -e "${RED}Invalid argument: $1${NC}"
				exit 1
			fi
			;;
		esac
	fi

	# Interactive menu mode
	while true; do
		show_menu
		read -r choice

		case $choice in
		[0-9]*)
			if [ "$choice" -gt 0 ] && [ "$choice" -le ${#SORTED_STATIONS[@]} ]; then
				choice=$((choice - 1))
				station_name="${SORTED_STATIONS[$choice]}"
				play_radio "${RADIOS[$station_name]}" "$station_name" "true"
				# Wait for user input before returning to the menu
				echo -e "${GREEN}Press any key to return to the menu...${NC}"
				read -n 1 -s
			else
				echo -e "${RED}Invalid station number!${NC}"
				sleep 1
			fi
			;;
		r | R)
			random_idx=$((RANDOM % ${#SORTED_STATIONS[@]}))
			random_station="${SORTED_STATIONS[$random_idx]}"
			echo -e "${GREEN}Randomly selected: $random_station${NC}"
			play_radio "${RADIOS[$random_station]}" "$random_station" "true"
			# Wait for user input before returning to the menu
			echo -e "${GREEN}Press any key to return to the menu...${NC}"
			read -n 1 -s
			;;
		s | S)
			echo -e "Enter search term: "
			read -r search_term
			search_radio "$search_term"
			# Wait for user input before returning to the menu
			echo -e "${GREEN}Press any key to return to the menu...${NC}"
			read -n 1 -s
			;;
		f | F)
			echo -e "${BLUE}Favorites:${NC}"
			while read -r favorite; do
				if [ -n "$favorite" ]; then
					echo "$favorite"
					echo "1) Play  2) Remove  3) Next"
					read -r fchoice
					case $fchoice in
					1)
						play_radio "${RADIOS[$favorite]}" "$favorite" "true"
						# Wait for user input before returning to the menu
						echo -e "${GREEN}Press any key to return to the menu...${NC}"
						read -n 1 -s
						break
						;;
					2) remove_from_favorites "$favorite" ;;
					*) continue ;;
					esac
				fi
			done <"$FAVORITES_FILE"
			;;
		h | H)
			echo -e "${BLUE}Recently played:${NC}"
			tail -n 10 "$HISTORY_FILE"
			read -r
			;;
		v | V)
			echo -e "Enter new volume (0-100): "
			read -r new_vol
			if [[ "$new_vol" =~ ^[0-9]+$ ]] && [ "$new_vol" -ge 0 ] && [ "$new_vol" -le 100 ]; then
				change_volume "$new_vol"
			else
				echo -e "${RED}Invalid volume level!${NC}"
				sleep 1
			fi
			;;
		p | P)
			# Toggle between VLC and MPV
			if [[ "$PLAYER" == "cvlc" ]]; then
				PLAYER="mpv"
				echo -e "${GREEN}Switched to MPV player${NC}"
			else
				PLAYER="cvlc"
				echo -e "${GREEN}Switched to VLC player${NC}"
			fi
			sleep 1
			;;
		q | Q)
			echo -e "${GREEN}Goodbye!${NC}"
			cleanup
			;;
		*)
			echo -e "${RED}Invalid choice!${NC}"
			sleep 1
			;;
		esac
	done
}

# ==============================================================================
# VRADIO (ported from osc-vradio.sh) -- preset launcher for station 1
# ==============================================================================
vradio_main() {
	# Stop any currently running stream player
	pkill -f cvlc 2>/dev/null
	pkill -f 'mpv --no-video' 2>/dev/null

	# Clear stale state so the preset toggle reliably starts playback
	rm -f "$PID_FILE" "$NOW_PLAYING_FILE"

	# Wait for processes to clean up
	sleep 1

	# Start the radio engine with the preset station (station 1)
	radio_main -t 1
}

# ==============================================================================
# TV (ported from osc-tv-splitter.sh) -- IPTV channel splitter/player
# ==============================================================================
tv_main() {
	# Configuration
	local APPS_DIR="$HOME/.apps"
	local IPTV_DIR="$APPS_DIR/iptv"
	local CHANNELS_DIR="$HOME/.iptv/channels"
	local SCRIPTS_DIR="$HOME/.iptv/bin"

	# Check dependencies
	info "Checking dependencies..."
	local cmd
	for cmd in git mpv; do
		have "$cmd" || error "Required command not found: $cmd"
	done
	success "Dependencies OK"

	# Create necessary directories
	info "Creating directories..."
	mkdir -p "$APPS_DIR" "$CHANNELS_DIR" "$SCRIPTS_DIR" || error "Failed to create directories"
	success "Directories created"

	# Clone or update iptv repository
	info "Managing IPTV repository..."
	if [ -d "$IPTV_DIR" ]; then
		cd "$IPTV_DIR" || error "Cannot change to IPTV directory"
		git pull origin master >/dev/null 2>&1 || error "Git pull failed"
		success "Repository updated"
	else
		cd "$APPS_DIR" || error "Cannot change to apps directory"
		git clone --depth 1 https://github.com/iptv-org/iptv >/dev/null 2>&1 || error "Git clone failed"
		success "Repository cloned"
	fi

	# Validate M3U file
	local M3U_FILE="$IPTV_DIR/streams/tr.m3u"
	[ -f "$M3U_FILE" ] || error "M3U file not found: $M3U_FILE"
	[ -r "$M3U_FILE" ] || error "M3U file not readable"
	success "M3U file validated"

	# Process tr.m3u file
	info "Processing M3U file..."
	cd "$IPTV_DIR/streams" || error "Cannot change to streams directory"

	# Clean old files
	rm -f "$CHANNELS_DIR"/*.m3u 2>/dev/null
	rm -f "$SCRIPTS_DIR"/tv-* 2>/dev/null

	# Initialize counters
	local processed_count=0
	local current_file=""
	local line channel_id channel_name safe_id script_name

	# Process file line by line
	while IFS= read -r line || [ -n "$line" ]; do
		if [[ $line == \#EXTINF* ]]; then
			# Extract channel ID
			channel_id=$(echo "$line" | grep -o 'tvg-id="[^"]*"' | cut -d'"' -f2)

			# Extract channel name (everything after the last comma)
			channel_name=$(echo "$line" | sed 's/.*,//')

			if [ -n "$channel_id" ]; then
				# Sanitize channel ID for filename
				safe_id=$(echo "$channel_id" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9._-]/_/g')

				current_file="$CHANNELS_DIR/${safe_id}.m3u"
				script_name="tv-${safe_id}"

				# Create M3U file
				echo "$line" >"$current_file" || error "Failed to create channel file"

				# Create executable script for this channel
				cat >"$SCRIPTS_DIR/$script_name" <<EOF
#!/usr/bin/env bash
# TV Script for: $channel_name
# Channel ID: $channel_id
mpv --no-resume-playback --title="$channel_name" "$current_file"
EOF
				chmod +x "$SCRIPTS_DIR/$script_name" || error "Failed to make script executable"

				((processed_count++))
			else
				current_file=""
			fi

		elif [[ $line == http* ]] && [ -n "$current_file" ]; then
			# Add stream URL to current channel file
			echo "$line" >>"$current_file" || error "Failed to append URL to channel file"
		fi

	done <"tr.m3u"

	success "Processing completed"

	# Show results
	echo
	echo "==============================================="
	echo -e "${GREEN}Process completed successfully!${NC}"
	echo "==============================================="
	echo "📺 Channels processed: $processed_count"
	echo "📁 M3U files: $CHANNELS_DIR"
	echo "🎬 TV scripts: $SCRIPTS_DIR"
	echo
	echo "🚀 Usage:"
	echo "   Add to PATH: export PATH=\"$SCRIPTS_DIR:\$PATH\""
	echo "   Then run: tv-<channel-name>"
	echo
	echo "📋 Sample channels:"
	find "$SCRIPTS_DIR" -name "tv-*" -type f | head -5 | while read -r script; do
		echo "   $(basename "$script")"
	done

	local total_scripts
	total_scripts=$(find "$SCRIPTS_DIR" -name "tv-*" -type f | wc -l)
	if [ "$total_scripts" -gt 5 ]; then
		echo "   ... and $((total_scripts - 5)) more"
	fi

	echo
	echo "✨ All done!"
}

# ==============================================================================
# LOFI (ported from lofi.sh) -- toggle a YouTube lo-fi radio stream
# ==============================================================================
lofi_main() {
	if ps aux | grep mpv | grep -v grep >/dev/null; then
		pkill mpv
	else
		mpv_play --no-video "https://www.youtube.com/live/jfKfPfyJRdk?si=OF0HKrYFFj33BzMo"
	fi
}

# ==============================================================================
# Usage / dispatcher
# ==============================================================================
usage() {
	cat <<'EOF'
Unified stream player for margo (radio / vradio / tv / lofi)

Usage: osc-stream <subcommand> [args]

Subcommands:
  radio [args]   Interactive internet-radio player (mpv/cvlc). DEFAULT if omitted.
                 Flags: -t N (toggle station N), -s (stop), -l (list),
                        -p (switch player), -h (radio help), N (play station N)
  vradio         Preset launcher: stop current stream, then play station 1
  tv [args]      IPTV channel splitter/player (iptv-org streams)
  lofi           Toggle a YouTube lo-fi radio stream (mpv + yt-dlp)
  help           Show this help

With no subcommand, osc-stream behaves like 'radio' (muscle memory preserved).
EOF
}

main() {
	case "${1:-}" in
	radio)
		shift
		radio_main "$@"
		;;
	vradio)
		shift
		vradio_main "$@"
		;;
	tv)
		shift
		tv_main "$@"
		;;
	lofi)
		shift
		lofi_main "$@"
		;;
	help | --help | -h)
		usage
		exit 0
		;;
	*)
		# Default: behave like the radio engine (preserves osc-radio invocation)
		radio_main "$@"
		;;
	esac
}

main "$@"
