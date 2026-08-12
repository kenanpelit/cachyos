#!/usr/bin/env bash
# ==============================================================================
# Script: profile_chrome.sh
# Description: Google Chrome profile launcher (fresh-isolated instances).
# Usage: profile_chrome.sh [profile_name|--webapp] [options]
# ==============================================================================
#   Özellikler (profile_brave.sh'in yalın chrome forku):
#   - Her profil KENDİ izole user-data-dir'inde açılır: ~/.chrome/<sınıf>
#     (tohumlama yok — ilk açılışta bir kez giriş yap, veri orada kalıcı olur)
#   - Hazır web-app kısayolları (whatsapp, youtube, tiktok, spotify, discord)
#   - SOCKS5/HTTP proxy desteği, incognito, özel pencere sınıfı/başlık
#   - Wayland (ozone) bayrakları
#
#   Not: Brave'in Local State / jq tabanlı profil çözümleme + tohumlama makinesi
#   burada YOK — "hepsi taze izole" modeli bunu gereksiz kılıyor.
# ==============================================================================

set -eo pipefail

readonly SCRIPT_VERSION="1.0"
readonly SCRIPT_NAME="$(basename "$0")"

# Renkler / semboller
readonly BOLD="\033[1m"
readonly RED="\033[31m"
readonly GREEN="\033[32m"
readonly YELLOW="\033[33m"
readonly BLUE="\033[34m"
readonly RESET="\033[0m"
readonly SUCCESS="✓"
readonly ERROR="✗"
readonly WARNING="⚠"
readonly INFO="ℹ"

# Konfigürasyon
readonly CONFIG_FILE="${HOME}/.config/chrome-launcher/config.conf"
readonly LOG_FILE="${HOME}/.config/chrome-launcher/chrome-launcher.log"

# Varsayılan konfigürasyon
# CHROME_CMD "auto" ise google-chrome-stable → google-chrome → chrome sırasıyla çözülür.
CHROME_CMD="${CHROME_CMD:-auto}"
# Her profilin izole user-data-dir kökü. Profiller ~/.chrome/<sınıf> altında yaşar.
ISOLATED_ROOT="${ISOLATED_ROOT:-${HOME}/.chrome}"

# Wayland varsayılan bayrakları. Vulkan + ozone-wayland uyumsuz (Chromium 113+),
# ANGLE/OpenGL render path'e düşürüyoruz; VAAPI donanım decode korunur.
# WaylandWindowDecorations CSD için (margo SSD/CSD policy ile uyumlu).
DEFAULT_FLAGS=(
	"--restore-last-session"
	"--ozone-platform=wayland"
	"--enable-features=UseOzonePlatform,WaylandWindowDecorations,VaapiVideoDecoder,TouchpadOverscrollHistoryNavigation"
	"--disable-features=Vulkan"
)

# Proxy ayarları
PROXY_ENABLED=false
PROXY_HOST="127.0.0.1"
PROXY_PORT="4999"
PROXY_TYPE="socks5"

# Loglama
log() {
	local level="$1"
	shift
	local message="$*"
	local timestamp
	timestamp=$(date '+%Y-%m-%d %H:%M:%S')

	mkdir -p "$(dirname "$LOG_FILE")" >/dev/null 2>&1 || true
	if [[ -w "$LOG_FILE" || (! -e "$LOG_FILE" && -w "$(dirname "$LOG_FILE")") ]]; then
		echo "[$timestamp] [$level] $message" >>"$LOG_FILE" || true
	fi

	case "$level" in
	"ERROR") echo -e "${RED}${ERROR} $message${RESET}" >&2 ;;
	"WARN") echo -e "${YELLOW}${WARNING} $message${RESET}" ;;
	"INFO") echo -e "${BLUE}${INFO} $message${RESET}" ;;
	"SUCCESS") echo -e "${GREEN}${SUCCESS} $message${RESET}" ;;
	*) echo "$message" ;;
	esac
}

# Konfigürasyon dosyasını yükle (yoksa varsayılan oluştur)
load_config() {
	if [[ -f "$CONFIG_FILE" ]]; then
		# shellcheck source=/dev/null
		source "$CONFIG_FILE"
	else
		create_default_config
	fi
}

create_default_config() {
	mkdir -p "$(dirname "$CONFIG_FILE")"
	cat >"$CONFIG_FILE" <<'EOF'
# Chrome Launcher Konfigürasyonu

# Chrome komutu (auto, google-chrome-stable, google-chrome, chrome, /tam/yol)
CHROME_CMD="auto"

# İzole profil kökü (her profil ~/.chrome/<sınıf> altında)
ISOLATED_ROOT="${HOME}/.chrome"

# Proxy ayarları
PROXY_HOST="127.0.0.1"
PROXY_PORT="4999"
PROXY_TYPE="socks5"

# Ek Chrome bayrakları (boşlukla ayrılmış)
CUSTOM_FLAGS=""
EOF
	log "SUCCESS" "Varsayılan konfigürasyon oluşturuldu: $CONFIG_FILE"
}

# Chrome ikilisini çöz
resolve_chrome_cmd() {
	local requested="${CHROME_CMD:-auto}"
	local candidate=""
	local -a candidates=()

	# Açıkça bir yol/komut verildiyse önce onu dene.
	if [[ "$requested" != "auto" && -n "$requested" ]]; then
		candidates+=("$requested")
	fi
	candidates+=(
		"google-chrome-stable"
		"google-chrome"
		"chrome"
		"/usr/bin/google-chrome-stable"
		"/usr/bin/google-chrome"
	)

	for candidate in "${candidates[@]}"; do
		if [[ "$candidate" == */* ]]; then
			[[ -x "$candidate" ]] && {
				CHROME_CMD="$candidate"
				return 0
			}
		elif command -v "$candidate" &>/dev/null; then
			CHROME_CMD="$(command -v "$candidate")"
			return 0
		fi
	done
	return 1
}

# ---- Hazır web-app başlatıcıları --------------------------------------------
# Her web-app KENDİ profil adını (dolayısıyla kendi ~/.chrome/<ad> dizinini) alır.
launch_app() {
	local app_name="$1"
	local app_url="$2"
	local profile="${3:-kenp}"
	shift 3
	log "SUCCESS" "$app_name başlatılıyor..."
	# --app=... zaten ayrı bir uygulama penceresi açar.
	"$0" "$profile" --app="$app_url" --class="$app_name" --title="$app_name" "$@"
}

launch_whatsapp() { launch_app "WhatsApp" "https://web.whatsapp.com" "whatsapp" "$@"; }
launch_youtube() { launch_app "YouTube" "https://youtube.com" "youtube" "$@"; }
launch_tiktok() { launch_app "TikTok" "https://tiktok.com" "tiktok" "$@"; }
launch_spotify() { launch_app "Spotify" "https://open.spotify.com/" "spotify" "$@"; }
launch_discord() {
	local discord_url
	discord_url=$(pass discord-channels 2>/dev/null || echo "https://discord.com/app")
	launch_app "Discord" "$discord_url" "discord" "$@"
}

launch_proxy() {
	log "SUCCESS" "Proxy ile Chrome başlatılıyor"
	PROXY_ENABLED=true
	"$0" "proxy" --class=ProxyBrowser --title="Proxy Browser" "$@"
}

# Bir profil için çalışan Chrome örneklerini kapat
kill_profile_chrome() {
	local class="$1"
	log "INFO" "'$class' için çalışan Chrome örnekleri aranıyor"
	local pids
	pids=$(pgrep -f "chrome.*user-data-dir=${ISOLATED_ROOT}/${class}" || true)
	if [[ -n "$pids" ]]; then
		echo "$pids" | xargs kill -TERM 2>/dev/null || true
		sleep 2
		pids=$(pgrep -f "chrome.*user-data-dir=${ISOLATED_ROOT}/${class}" || true)
		[[ -n "$pids" ]] && echo "$pids" | xargs kill -KILL 2>/dev/null || true
		log "SUCCESS" "Profil örnekleri kapatıldı"
	else
		log "INFO" "Çalışan örnek bulunamadı"
	fi
}

kill_all_chrome() {
	log "WARN" "Tüm Chrome örnekleri kapatılıyor"
	pkill -TERM chrome 2>/dev/null || true
	sleep 2
	pkill -KILL chrome 2>/dev/null || true
	log "SUCCESS" "Tüm Chrome örnekleri kapatıldı"
}

list_profiles() {
	echo -e "${BOLD}İzole Chrome profilleri (${ISOLATED_ROOT}):${RESET}"
	if [[ -d "$ISOLATED_ROOT" ]]; then
		find "$ISOLATED_ROOT" -mindepth 1 -maxdepth 1 -type d -printf '  %f\n' 2>/dev/null | sort -f
	else
		echo -e "${YELLOW}  Henüz profil oluşturulmamış${RESET}"
	fi
}

usage() {
	echo -e "${BOLD}Chrome Profil Başlatıcı v${SCRIPT_VERSION}${RESET}"
	echo
	echo -e "${BOLD}Kullanım:${RESET}"
	echo -e "  $SCRIPT_NAME ${BOLD}<profil_ismi>${RESET} [seçenekler] [chrome_parametreleri]"
	echo -e "  $SCRIPT_NAME ${BOLD}--whatsapp|--youtube|--tiktok|--spotify|--discord${RESET}"
	echo
	echo -e "${BOLD}Seçenekler:${RESET}"
	echo "  --class=SINIF        Pencere sınıfını (ve izole dizin adını) ayarlar"
	echo "  --title=BASLIK       Pencere başlığını ayarlar"
	echo "  --separate           Ayrı user-data-dir kullan (varsayılan Wayland'de)"
	echo "  --no-separate        Tek instance davranışı"
	echo "  --incognito          İnkognito modunda başlat"
	echo "  --proxy[=host:port]  Proxy ile başlat"
	echo "  --proxy-type=TYPE    Proxy türü (socks5, http)"
	echo "  --kill-profile       Bu profil için çalışan örnekleri kapat"
	echo "  --kill-all           Tüm Chrome örneklerini kapat"
	echo "  --list-profiles      İzole profilleri listele"
	echo "  --version, --help    Sürüm / bu yardım"
	echo
	list_profiles
	exit "${1:-0}"
}

main() {
	load_config

	if ! resolve_chrome_cmd; then
		log "ERROR" "google-chrome bulunamadı (google-chrome-stable/google-chrome/chrome)"
		exit 1
	fi

	[[ $# -eq 0 ]] && usage 0

	# Özel ilk-parametreler
	case "$1" in
	--version)
		echo "Chrome Launcher v$SCRIPT_VERSION"
		exit 0
		;;
	--list-profiles)
		list_profiles
		exit 0
		;;
	--whatsapp) shift; launch_whatsapp "$@"; exit $? ;;
	--youtube) shift; launch_youtube "$@"; exit $? ;;
	--tiktok) shift; launch_tiktok "$@"; exit $? ;;
	--spotify) shift; launch_spotify "$@"; exit $? ;;
	--discord) shift; launch_discord "$@"; exit $? ;;
	--proxy) shift; launch_proxy "$@"; exit $? ;;
	--kill-all) kill_all_chrome; exit 0 ;;
	--help | -h) usage 0 ;;
	esac

	# İlk parametre = profil adı
	local profile_name="$1"
	shift

	local window_class=""
	local window_title=""
	local chrome_args=()
	local kill_profile=false
	local incognito_mode=false
	local separate_mode="auto"

	while [[ $# -gt 0 ]]; do
		case "${1:-}" in
		--class=*) window_class="${1#*=}" ;;
		--class)
			shift
			[[ -z "${1:-}" ]] && { log "ERROR" "--class bir değer bekliyor"; exit 1; }
			window_class="$1"
			;;
		--title=*) window_title="${1#*=}" ;;
		--title)
			shift
			[[ -z "${1:-}" ]] && { log "ERROR" "--title bir değer bekliyor"; exit 1; }
			window_title="$1"
			;;
		--separate) separate_mode="true" ;;
		--no-separate) separate_mode="false" ;;
		--proxy=*)
			IFS=':' read -r PROXY_HOST PROXY_PORT <<<"${1#*=}"
			PROXY_ENABLED=true
			;;
		--proxy) PROXY_ENABLED=true ;;
		--proxy-host=*) PROXY_HOST="${1#*=}"; PROXY_ENABLED=true ;;
		--proxy-port=*) PROXY_PORT="${1#*=}"; PROXY_ENABLED=true ;;
		--proxy-type=*) PROXY_TYPE="${1#*=}"; PROXY_ENABLED=true ;;
		--kill-profile) kill_profile=true ;;
		--incognito) incognito_mode=true ;;
		--help | -h) usage 0 ;;
		*) [[ -n "${1:-}" ]] && chrome_args+=("$1") ;;
		esac
		shift
	done

	# "proxy" profili otomatik proxy açar
	if [[ "$profile_name" == "proxy" && "$PROXY_ENABLED" == false ]]; then
		PROXY_ENABLED=true
		log "INFO" "proxy profili seçildi, proxy otomatik etkinleştirildi"
	fi

	# Pencere ayarları (izole dizin adı window_class'tan gelir)
	[[ -z "$window_class" ]] && window_class="$profile_name"
	[[ -z "$window_title" ]] && window_title="$profile_name Browser"

	if $incognito_mode; then
		window_title="$window_title (İnkognito)"
		window_class="${window_class}_incognito"
		log "INFO" "İnkognito modu etkinleştirildi"
	fi

	$kill_profile && kill_profile_chrome "$window_class"

	# separate_mode auto: Wayland için aç, X11 için kapalı
	if [[ "$separate_mode" == "auto" ]]; then
		if [[ -n "${WAYLAND_DISPLAY:-}" || "${XDG_SESSION_TYPE:-}" == "wayland" ]]; then
			separate_mode="true"
		else
			separate_mode="false"
		fi
	fi

	# Komut oluştur
	local cmd=("$CHROME_CMD")
	if [[ "$separate_mode" == "true" ]]; then
		# Taze izole: sadece dizini oluştur, Chrome kendi Default'unu tohumlar.
		local isolated_dir="${ISOLATED_ROOT}/${window_class}"
		mkdir -p "$isolated_dir"
		cmd+=("--user-data-dir=$isolated_dir")
	fi
	cmd+=("--profile-directory=Default")

	if $incognito_mode; then
		cmd+=("--incognito")
		cmd+=("${DEFAULT_FLAGS[@]}")
	else
		cmd+=("${DEFAULT_FLAGS[@]}")
	fi

	# Özel bayraklar (config)
	if [[ -n "${CUSTOM_FLAGS:-}" ]]; then
		# shellcheck disable=SC2206
		cmd+=($CUSTOM_FLAGS)
	fi

	# Proxy
	if [[ "$PROXY_ENABLED" == true ]]; then
		log "INFO" "Proxy: ${PROXY_TYPE}://${PROXY_HOST}:${PROXY_PORT}"
		cmd+=("--proxy-server=${PROXY_TYPE}://${PROXY_HOST}:${PROXY_PORT}")
		cmd+=("--host-resolver-rules=MAP * ~NOTFOUND, EXCLUDE ${PROXY_HOST}")
		cmd+=("--proxy-bypass-list=<local>")
	fi

	# Pencere sınıfı/başlık
	cmd+=("--class=$window_class")
	cmd+=("--window-name=$window_title")

	# Ek parametreler (--app=, --app-id=, url, ...)
	[[ ${#chrome_args[@]} -gt 0 ]] && cmd+=("${chrome_args[@]}")

	log "SUCCESS" "Chrome başlatılıyor: $profile_name  (dizin: ${ISOLATED_ROOT}/${window_class})"

	if "${cmd[@]}" >/dev/null 2> >(tail -n 20 >&2) & then
		local chrome_pid=$!
		log "INFO" "Chrome başlatıldı (PID: $chrome_pid)"
		sleep 1
	else
		log "ERROR" "Chrome başlatılamadı"
		return 1
	fi
}

main "$@"
