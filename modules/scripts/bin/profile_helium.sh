#!/usr/bin/env bash
# ==============================================================================
# Script: profile_helium.sh
# Description: Helium Profile Launcher with window management and proxy support
# Usage: profile_helium.sh [profile_name] [options]
# ==============================================================================
#   Özellikler:
#   - Profil bazlı Helium başlatma
#   - Özel pencere sınıfı ve başlık ayarlama
#   - Komut satırı argümanlarını destekleme
#   - Profil listeleme ve yönetimi
#   - Hazır uygulama kısayolları (whatsapp, youtube, tiktok, spotify, discord)
#   - SOCKS5/HTTP Proxy Desteği
#   - Wayland ve dokunmatik yüzey desteği
#   - Yeni pencere zorlama özelliği
#   - İnkognito mod desteği
#   - Yeni profil oluşturma ve silme
#   - Yapılandırma dosyası desteği
#   - Gelişmiş hata yönetimi ve loglama
#
#===============================================================================

set -eo pipefail

# Script sürümü
readonly SCRIPT_VERSION="2.0"
readonly SCRIPT_NAME="$(basename "$0")"

# Renk tanımlamaları
readonly BOLD="\033[1m"
readonly RED="\033[31m"
readonly GREEN="\033[32m"
readonly YELLOW="\033[33m"
readonly BLUE="\033[34m"
readonly CYAN="\033[36m"
readonly RESET="\033[0m"

# Semboller
readonly SUCCESS="✓"
readonly ERROR="✗"
readonly WARNING="⚠"
readonly INFO="ℹ"

# Konfigürasyon dosyası
readonly CONFIG_FILE="${HOME}/.config/helium-launcher/config.conf"
readonly LOG_FILE="${HOME}/.config/helium-launcher/helium-launcher.log"

	# Varsayılan konfigürasyon
	HELIUM_CMD="helium-browser"
	# Helium'in varsayılan user-data-dir'i (profil/Local State burada)
	LOCAL_STATE_PATH="${HOME}/.config/net.imput.helium/Local State"
	HELIUM_PROFILES_DIR="${HOME}/.config/net.imput.helium"
	# Niri/Hyprland'da farklı profilleri ayrı process + ayrı app-id ile açabilmek için
	# profile bazlı ayrı user-data-dir kullanırız; profil dizinini symlink'leyerek veri çoğaltmayız.
	ISOLATED_ROOT="${HOME}/.helium/isolated"
	# Widevine CDM yolu (gerekirse env ile override edilebilir)
	WIDEVINE_CDM_PATH="${WIDEVINE_CDM_PATH:-/usr/lib/chromium/WidevineCdm}"

# Wayland ve dokunmatik yüzey için varsayılan bayraklar
	DEFAULT_FLAGS=(
		"--restore-last-session"
		"--enable-features=TouchpadOverscrollHistoryNavigation,UseOzonePlatform,VaapiVideoDecoder"
		"--ozone-platform=wayland"
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
	local timestamp=$(date '+%Y-%m-%d %H:%M:%S')

	# Log dizinini oluştur
	mkdir -p "$(dirname "$LOG_FILE")" >/dev/null 2>&1 || true

	# Log dosyasına yaz
	if [[ -w "$LOG_FILE" || ( ! -e "$LOG_FILE" && -w "$(dirname "$LOG_FILE")" ) ]]; then
		echo "[$timestamp] [$level] $message" >>"$LOG_FILE" || true
	fi

	# Terminale de yazdır
	case "$level" in
	"ERROR")
		echo -e "${RED}${ERROR} $message${RESET}" >&2
		;;
	"WARN")
		echo -e "${YELLOW}${WARNING} $message${RESET}"
		;;
	"INFO")
		echo -e "${BLUE}${INFO} $message${RESET}"
		;;
	"SUCCESS")
		echo -e "${GREEN}${SUCCESS} $message${RESET}"
		;;
	*)
		echo "$message"
		;;
	esac
}

# Hata yakalama - sadece kritik hatalar için
error_handler() {
	local line_no=$1
	local error_code=$2

	# Sadece ciddi hataları yakala (1'den büyük çıkış kodları)
	if [[ $error_code -gt 1 ]]; then
		log "ERROR" "Script failed at line $line_no with exit code $error_code"
		exit "$error_code"
	fi
}

# Sadece ciddi hatalar için trap kur
trap 'error_handler ${LINENO} $?' ERR

# Konfigürasyon dosyasını yükle
load_config() {
	if [[ -f "$CONFIG_FILE" ]]; then
		# shellcheck source=/dev/null
		source "$CONFIG_FILE"
	else
		create_default_config
	fi
}

# Varsayılan konfigürasyon dosyası oluştur
create_default_config() {
	mkdir -p "$(dirname "$CONFIG_FILE")"
	cat >"$CONFIG_FILE" <<'EOF'
# Helium Launcher Konfigürasyonu

# Helium komutu
HELIUM_CMD="helium-browser"

# Proxy ayarları
PROXY_HOST="127.0.0.1"
PROXY_PORT="4999"
PROXY_TYPE="socks5"

# Ek Helium bayrakları (boşlukla ayrılmış)
CUSTOM_FLAGS=""

# Varsayılan profil
DEFAULT_PROFILE="Default"

# Debug modu (true/false)
DEBUG_MODE=false
EOF
	log "SUCCESS" "Varsayılan konfigürasyon dosyası oluşturuldu: $CONFIG_FILE"
}

# Debug modu kontrolü
debug() {
	[[ "${DEBUG_MODE:-false}" == "true" ]] && log "DEBUG" "$*"
}

# Gerekli bağımlılıkları kontrol et
check_dependencies() {
	local deps=("jq")
	local missing=()

	for dep in "${deps[@]}"; do
		if ! command -v "$dep" &>/dev/null; then
			missing+=("$dep")
		fi
	done

	# Helium komutunu kontrol et - farklı isimler dene
	local helium_found=false
	local helium_commands=(
		"helium-browser"
		"helium-wrapper"
		"/usr/bin/helium-browser"
		"/opt/helium-browser-bin/helium-wrapper"
		"/opt/helium-browser-bin/helium"
	)

	for helium_cmd in "${helium_commands[@]}"; do
		if [[ "$helium_cmd" == */* ]]; then
			if [[ -x "$helium_cmd" ]]; then
				HELIUM_CMD="$helium_cmd"
				helium_found=true
				log "INFO" "Helium bulundu: $helium_cmd"
				break
			fi
		elif command -v "$helium_cmd" &>/dev/null; then
			HELIUM_CMD="$helium_cmd"
			helium_found=true
			log "INFO" "Helium bulundu: $helium_cmd"
			break
		fi
	done

	if [[ "$helium_found" == false ]]; then
		missing+=("helium-browser")
	fi

	if [[ ${#missing[@]} -gt 0 ]]; then
		log "ERROR" "Eksik bağımlılıklar: ${missing[*]}"
		log "INFO" "Kurulum: helium-browser paketini yükleyin"
		exit 1
	fi
}

	# Kullanım bilgisi
	usage() {
	echo -e "${BOLD}Helium Profil Başlatıcı v${SCRIPT_VERSION}${RESET}"
	echo
	echo -e "${BOLD}Kullanım:${RESET}"
	echo -e "  $SCRIPT_NAME ${BOLD}<profil_ismi>${RESET} [seçenekler] [helium_parametreleri]"
	echo -e "  $SCRIPT_NAME ${BOLD}--whatsapp${RESET} [seçenekler]"
	echo -e "  $SCRIPT_NAME ${BOLD}--youtube${RESET} [seçenekler]"
	echo -e "  $SCRIPT_NAME ${BOLD}--spotify${RESET} [seçenekler]"
	echo -e "  $SCRIPT_NAME ${BOLD}--discord${RESET} [seçenekler]"
	echo
	echo -e "${BOLD}Seçenekler:${RESET}"
	echo "  --class=SINIF              Pencere sınıfını ayarlar"
	echo "  --title=BASLIK             Pencere başlığını ayarlar"
	echo "  --proxy[=host:port]        Proxy ile başlatır"
	echo "  --Proxy                    Proxy profili ile başlatır"
	echo "  --proxy-type=TYPE          Proxy türü (socks5, http, https)"
	echo "  --separate                 Her profil için ayrı Helium instance (user-data-dir) kullan"
	echo "  --no-separate              Tek instance davranışı (varsayılan Chromium)"
	echo "  --pid-file=PATH            Başlatılan Helium PID bilgisini PATH'e yaz"
	echo "  --pid-file PATH            Aynısı"
	echo "  --incognito                İnkognito modunda başlatır"
	echo "  --kill-profile             Bu profil için çalışan örnekleri kapat"
	echo "  --kill-all                 Tüm Helium örneklerini kapat"
	echo "  --create-profile=ISIM      Yeni profil oluştur"
	echo "  --delete-profile=ISIM      Profil sil"
	echo "  --list-profiles            Profilleri listele"
	echo "  --config                   Konfigürasyon dosyasını düzenle"
	echo "  --version                  Sürüm bilgisini göster"
	echo "  --help, -h                 Bu yardımı göster"
	echo
	echo -e "${BOLD}Hazır Uygulamalar:${RESET}"
	echo "  --whatsapp                 WhatsApp Web"
	echo "  --youtube                  YouTube"
	echo "  --tiktok                   TikTok"
	echo "  --spotify                  Spotify Web Player"
	echo "  --discord                  Discord Web"
	echo
	echo -e "${BOLD}Örnekler:${RESET}"
	echo "  $SCRIPT_NAME \"İş Profili\" --class=WorkBrowser"
	echo "  $SCRIPT_NAME Default --incognito"
	echo "  $SCRIPT_NAME --whatsapp"
	echo "  $SCRIPT_NAME Proxy --proxy=127.0.0.1:9050"
	echo
		list_profiles
		exit "${1:-0}"
	}

	ensure_isolated_userdata() {
		local isolated_dir="$1"
		local src_userdata_dir="${2:-$HELIUM_PROFILES_DIR}"
		mkdir -p "$isolated_dir"

		# Local State olmadan Helium bazı profilleri "sıfırdan" açıp uyarı/hata verebiliyor.
		# Symlink yerine kopyalıyoruz: her instance kendi Local State'ini yazabilsin.
		if [[ -f "${src_userdata_dir}/Local State" && ! -f "${isolated_dir}/Local State" ]]; then
			cp -f "${src_userdata_dir}/Local State" "${isolated_dir}/Local State" 2>/dev/null || true
		fi

		# First Run yoksa ilk kurulum ekranları/uyarıları çıkabiliyor.
		if [[ -f "${src_userdata_dir}/First Run" && ! -f "${isolated_dir}/First Run" ]]; then
			cp -f "${src_userdata_dir}/First Run" "${isolated_dir}/First Run" 2>/dev/null || true
		fi

		# Bazı sürümler "Last Version" dosyasına bakıyor.
		if [[ -f "${src_userdata_dir}/Last Version" && ! -f "${isolated_dir}/Last Version" ]]; then
			cp -f "${src_userdata_dir}/Last Version" "${isolated_dir}/Last Version" 2>/dev/null || true
		fi

		# Widevine marker dosyasını isolated user-data-dir içine yaz.
		ensure_widevine_marker "$isolated_dir"
	}

	ensure_widevine_marker() {
		local userdata_dir="$1"
		[[ -d "$userdata_dir" ]] || return 0
		[[ -d "$WIDEVINE_CDM_PATH" ]] || return 0

		local marker_dir="${userdata_dir}/WidevineCdm"
		local marker_file="${marker_dir}/latest-component-updated-widevine-cdm"
		mkdir -p "$marker_dir" 2>/dev/null || true
		printf '{"Path":"%s"}' "$WIDEVINE_CDM_PATH" >"$marker_file" 2>/dev/null || true
	}

	ensure_isolated_profile_dir() {
		local isolated_dir="$1"
		local profile_key="$2"
		local src_userdata_dir="${3:-$HELIUM_PROFILES_DIR}"
		local src="${src_userdata_dir}/${profile_key}"
		local dst="${isolated_dir}/${profile_key}"
		local seed_marker="${isolated_dir}/.profile_helium_seed_${profile_key}"

		if [[ ! -d "$src" ]]; then
			log "ERROR" "Kaynak profil dizini bulunamadı: $src"
			exit 1
		fi

		# Eğer Helium daha önce isolated_dir altında boş/bozuk bir profil dizini oluşturduysa,
		# veya önceki sürüm symlink bıraktıysa, bunu yedekleyip temiz bir kopya oluştur.
		local need_copy="false"
		if [[ -L "$dst" ]]; then
			need_copy="true"
		elif [[ -e "$dst" && ! -d "$dst" ]]; then
			log "ERROR" "Isolated profilde beklenmeyen dosya türü: $dst"
			exit 1
		elif [[ -d "$dst" ]]; then
			# "Preferences" yoksa genelde bozuk/yarım profildir.
			if [[ ! -f "$dst/Preferences" ]]; then
				need_copy="true"
			fi
		else
			need_copy="true"
		fi

		local desired_seed="$src_userdata_dir"
		local current_seed=""
		if [[ -f "$seed_marker" ]]; then
			current_seed="$(cat "$seed_marker" 2>/dev/null || true)"
		fi
		# Var olan isolated profiller, geçmişte farklı bir kaynaktan seed edilmiş olabilir.
		# Bu durumda (ve sadece src != dst iken) 1 kere re-seed yapıp marker yazıyoruz.
		if [[ "$src_userdata_dir" != "$isolated_dir" && "$current_seed" != "$desired_seed" ]]; then
			need_copy="true"
		fi

		if [[ "$need_copy" == "true" ]]; then
			local backup=""
			if [[ -e "$dst" ]]; then
				backup="${dst}.bak-$(date +%Y%m%d%H%M%S)"
				log "WARN" "Isolated profile '$profile_key' yedekleniyor: $dst -> $backup"
				mv "$dst" "$backup" 2>/dev/null || true
			fi

			log "INFO" "Profil kopyalanıyor (ilk kurulum): $src -> $dst"
			# -a: izinler/symlink/timestamp; -L: kaynak içindeki symlink'leri dereference et
			cp -aL "$src" "$dst" 2>/dev/null || {
				log "ERROR" "Profil kopyalanamadı: $src -> $dst"
				[[ -n "$backup" ]] && log "INFO" "Yedek duruyor: $backup"
				exit 1
			}
			echo "$desired_seed" >"$seed_marker" 2>/dev/null || true
		elif [[ "$src_userdata_dir" == "$isolated_dir" && ! -f "$seed_marker" ]]; then
			echo "$desired_seed" >"$seed_marker" 2>/dev/null || true
		fi
	}

# Profil listesi (geliştirilmiş)
iter_local_state_files() {
	if [[ -f "$LOCAL_STATE_PATH" ]]; then
		printf '%s\n' "$LOCAL_STATE_PATH"
	fi

	if [[ -d "$ISOLATED_ROOT" ]]; then
		find "$ISOLATED_ROOT" -mindepth 2 -maxdepth 2 -type f -name 'Local State' 2>/dev/null | sort
	fi
}

profile_key_from_state() {
	local profile_name="$1"
	local local_state_path="$2"
	local profile_key=""

	# Exact match
	if profile_key=$(jq -r --arg name "$profile_name" \
		'.profile.info_cache | to_entries | .[] |
		select(.value.name == $name) | .key' "$local_state_path" 2>/dev/null | head -n1); then
		[[ -n "$profile_key" ]] && {
			printf '%s\n' "$profile_key"
			return 0
		}
	fi

	# Case-insensitive fallback
	if profile_key=$(jq -r --arg name "$profile_name" \
		'.profile.info_cache | to_entries | .[] |
		select((.value.name | ascii_downcase) == ($name | ascii_downcase)) | .key' \
		"$local_state_path" 2>/dev/null | head -n1); then
		[[ -n "$profile_key" ]] && {
			printf '%s\n' "$profile_key"
			return 0
		}
	fi

	return 1
}

resolve_profile_source() {
	local profile_name="$1"
	local local_state_path=""
	local profile_key=""
	local -a candidates=()
	local candidate=""
	local preferred_local_state="${ISOLATED_ROOT}/${profile_name}/Local State"
	local kenp_local_state="${ISOLATED_ROOT}/Kenp/Local State"
	local default_local_state="$LOCAL_STATE_PATH"

	add_candidate_unique() {
		local path="$1"
		local existing=""
		[[ -f "$path" ]] || return 0
		for existing in "${candidates[@]}"; do
			[[ "$existing" == "$path" ]] && return 0
		done
		candidates+=("$path")
	}

	# Priority:
	# 1) same-profile isolated Local State (most deterministic)
	# 2) default Helium Local State
	# 3) Kenp isolated Local State as canonical donor
	# 4) all other isolated Local State files (fallback)
	add_candidate_unique "$preferred_local_state"
	add_candidate_unique "$default_local_state"
	if [[ "${profile_name,,}" != "kenp" ]]; then
		add_candidate_unique "$kenp_local_state"
	fi

	if [[ -d "$ISOLATED_ROOT" ]]; then
		while IFS= read -r local_state_path; do
			add_candidate_unique "$local_state_path"
		done < <(find "$ISOLATED_ROOT" -mindepth 2 -maxdepth 2 -type f -name 'Local State' 2>/dev/null | sort)
	fi

	for candidate in "${candidates[@]}"; do
		if profile_key=$(profile_key_from_state "$profile_name" "$candidate"); then
			local_state_path="$candidate"
			printf '%s\t%s\n' "$local_state_path" "$profile_key"
			return 0
		fi
	done

	return 1
}

list_profiles() {
	echo -e "${BOLD}Mevcut profiller:${RESET}"

	local local_state_path=""
	local -a rows=()
	local row=""
	local has_any=0

	while IFS= read -r local_state_path; do
		[[ -f "$local_state_path" ]] || continue
		has_any=1
		while IFS= read -r row; do
			[[ -n "$row" ]] || continue
			rows+=("$row")
		done < <(jq -r '.profile.info_cache | to_entries[]? | "  \(.key): \(.value.name)"' "$local_state_path" 2>/dev/null || true)
	done < <(iter_local_state_files)

	if [[ "$has_any" -eq 0 ]]; then
		log "ERROR" "Helium profil bilgisi bulunamadı (Local State yok)"
		return 1
	fi

	if [[ "${#rows[@]}" -eq 0 ]]; then
		echo -e "${YELLOW}  Henüz profil oluşturulmamış${RESET}"
	else
		printf '%s\n' "${rows[@]}" | awk '!seen[$0]++' | sort -f
	fi

	echo
}

# Profil silme
delete_profile() {
	local profile_name="$1"

	if [[ -z "$profile_name" ]]; then
		log "ERROR" "Profil ismi belirtilmedi"
		return 1
	fi

	# Profil anahtarını bul
	local profile_key
	if ! profile_key=$(jq -r --arg name "$profile_name" \
		'.profile.info_cache | to_entries | .[] | 
		select(.value.name == $name) | .key' "$LOCAL_STATE_PATH" 2>/dev/null); then
		log "ERROR" "Profil bilgisi okunamadı"
		return 1
	fi

	if [[ -z "$profile_key" ]]; then
		log "ERROR" "Profil bulunamadı: $profile_name"
		return 1
	fi

	# Onay al
	echo -e "${YELLOW}${WARNING} '$profile_name' profili silinecek. Emin misiniz? [y/N]${RESET}"
	read -r confirmation

	if [[ ! "$confirmation" =~ ^[Yy]$ ]]; then
		log "INFO" "İşlem iptal edildi"
		return 0
	fi

	# Profil dizinini sil
	local profile_path="$HELIUM_PROFILES_DIR/$profile_key"
	if [[ -d "$profile_path" ]]; then
		rm -rf "$profile_path"
		log "SUCCESS" "Profil dizini silindi: $profile_path"
	fi

	log "SUCCESS" "Profil '$profile_name' başarıyla silindi"
}

# Yeni profil oluşturma (geliştirilmiş)
create_profile() {
	local profile_name="$1"
	local icon_path="${2:-}"

	if [[ -z "$profile_name" ]]; then
		log "ERROR" "Profil ismi boş olamaz"
		return 1
	fi

	# Profil ismi kontrolü
	if [[ "$profile_name" =~ [^a-zA-Z0-9\ \-\_] ]]; then
		log "ERROR" "Profil ismi sadece harf, rakam, boşluk, tire ve alt çizgi içerebilir"
		return 1
	fi

	log "INFO" "Yeni profil oluşturuluyor: $profile_name"

	# Mevcut profilleri kontrol et
	if [[ -f "$LOCAL_STATE_PATH" ]]; then
		local existing_profile
		if existing_profile=$(jq -r --arg name "$profile_name" \
			'.profile.info_cache | to_entries | .[] | 
			select(.value.name == $name) | .key' "$LOCAL_STATE_PATH" 2>/dev/null) && [[ -n "$existing_profile" ]]; then
			log "WARN" "Profil zaten mevcut: $profile_name"
			return 0
		fi
	fi

	# Yeni profil numarası oluştur
	local profile_number=1
	while [[ -d "$HELIUM_PROFILES_DIR/Profile $profile_number" ]]; do
		((profile_number++))
	done

	local profile_dir="Profile $profile_number"
	local profile_path="$HELIUM_PROFILES_DIR/$profile_dir"

	# Profil dizinini oluştur
	mkdir -p "$profile_path"

	# Özel ikon ayarla
	if [[ -n "$icon_path" && -f "$icon_path" ]]; then
		log "INFO" "Profil ikonu ayarlanıyor: $icon_path"
		cp "$icon_path" "$profile_path/icon.png"
	fi

	# Profili başlat
	log "INFO" "Helium başlatılıyor, profili yapılandırın ve kapatın"
	"$HELIUM_CMD" "--profile-directory=$profile_dir" \
		"--profile-creation-name=$profile_name" \
		--no-first-run &

	local helium_pid=$!

	# Helium'in başlamasını bekle
	sleep 3

	# Helium kapanana kadar bekle
	wait "$helium_pid" 2>/dev/null || true

	log "SUCCESS" "Profil oluşturuldu: $profile_name"
	log "INFO" "Kullanım: $SCRIPT_NAME \"$profile_name\""

	return 0
}

# Uygulama başlatıcıları (geliştirilmiş)
	launch_app() {
		local app_name="$1"
		local app_url="$2"
		local profile="${3:-Kenp}"
	shift 3

	log "SUCCESS" "$app_name başlatılıyor..."

	# App-mode: `--app=...` zaten ayrı bir uygulama penceresi açar; `--new-window`
	# eklemek bazı durumlarda "normal browser window" davranışını tetikleyebiliyor.
		"$0" "$profile" --app="$app_url" \
			--class="$app_name" --title="$app_name" "$@"
	}

launch_whatsapp() { launch_app "WhatsApp" "https://web.whatsapp.com" "Kenp" "$@"; }
launch_youtube() { launch_app "YouTube" "https://youtube.com" "Kenp" "$@"; }
launch_tiktok() { launch_app "TikTok" "https://tiktok.com" "Kenp" "$@"; }
launch_spotify() { launch_app "Spotify" "https://open.spotify.com/" "Kenp" "$@"; }

launch_discord() {
	local discord_url
	discord_url=$(pass discord-channels 2>/dev/null || echo "https://discord.com/app")
	launch_app "Discord" "$discord_url" "Kenp" "$@"
}

# Proxy ile başlatma (geliştirilmiş)
launch_proxy() {
	log "SUCCESS" "Proxy ile Helium başlatılıyor"
	PROXY_ENABLED=true
	"$0" "Proxy" --class=ProxyBrowser --title="Proxy Browser" "$@"
}

# Profil için çalışan Helium örneklerini kapat (geliştirilmiş)
kill_profile_helium() {
	local profile_dir="$1"
	log "INFO" "Profil '$profile_dir' için çalışan Helium örnekleri aranıyor"

	local pids
	pids=$(pgrep -f "helium.*profile-directory=$profile_dir" || true)

	if [[ -n "$pids" ]]; then
		log "WARN" "Profil için çalışan Helium örnekleri bulundu, kapatılıyor"
		echo "$pids" | xargs kill -TERM 2>/dev/null || true
		sleep 2

		# Hala çalışan varsa zorla kapat
		pids=$(pgrep -f "helium.*profile-directory=$profile_dir" || true)
		if [[ -n "$pids" ]]; then
			echo "$pids" | xargs kill -KILL 2>/dev/null || true
		fi

		log "SUCCESS" "Profil örnekleri kapatıldı"
	else
		log "INFO" "Profil için çalışan Helium örneği bulunamadı"
	fi
}

# Tüm Helium örneklerini kapat
kill_all_helium() {
	log "WARN" "Tüm Helium örnekleri kapatılıyor"
	pkill -TERM helium 2>/dev/null || true
	sleep 2
	pkill -KILL helium 2>/dev/null || true
	log "SUCCESS" "Tüm Helium örnekleri kapatıldı"
}

# Konfigürasyon düzenleme
edit_config() {
	local editor="${EDITOR:-nano}"
	log "INFO" "Konfigürasyon dosyası düzenleniyor: $CONFIG_FILE"
	"$editor" "$CONFIG_FILE"
}

# Profil doğrulama
validate_profile() {
	local profile_name="$1"
	local local_state_path="${2:-$LOCAL_STATE_PATH}"

	if [[ -z "$local_state_path" || ! -f "$local_state_path" ]]; then
		log "ERROR" "Helium profil dosyası bulunamadı: $local_state_path"
		return 1
	fi

	local profile_key=""
	if ! profile_key=$(profile_key_from_state "$profile_name" "$local_state_path"); then
		profile_key=""
	fi

	if [[ -z "$profile_key" ]]; then
		log "ERROR" "Profil bulunamadı: $profile_name"
		list_profiles
		return 1
	fi

	echo "$profile_key"
}

# Ana işlev
	main() {
	# Konfigürasyonu yükle
	load_config

	# Bağımlılıkları kontrol et
	check_dependencies

	# Parametre kontrolü
	[[ $# -eq 0 ]] && usage 0

	# Özel parametreleri işle
	case "$1" in
	--version)
		echo "Helium Launcher v$SCRIPT_VERSION"
		exit 0
		;;
	--config)
		edit_config
		exit 0
		;;
	--list-profiles)
		list_profiles
		exit 0
		;;
	--create-profile=*)
		profile_name="${1#*=}"
		shift
		icon_path=""
		# Parametreleri işle
		while [[ $# -gt 0 ]]; do
			case "$1" in
			--icon=*)
				icon_path="${1#*=}"
				shift
				;;
			*)
				break
				;;
			esac
		done
		create_profile "$profile_name" "$icon_path"
		exit $?
		;;
	--delete-profile=*)
		profile_name="${1#*=}"
		delete_profile "$profile_name"
		exit $?
		;;
	--whatsapp)
		shift
		launch_whatsapp "$@"
		exit $?
		;;
	--youtube)
		shift
		launch_youtube "$@"
		exit $?
		;;
	--tiktok)
		shift
		launch_tiktok "$@"
		exit $?
		;;
	--spotify)
		shift
		launch_spotify "$@"
		exit $?
		;;
	--discord)
		shift
		launch_discord "$@"
		exit $?
		;;
	--proxy)
		shift
		launch_proxy "$@"
		exit $?
		;;
	--Proxy)
		shift
		launch_proxy "$@"
		exit $?
		;;
	--kill-all)
		kill_all_helium
		exit 0
		;;
	--help | -h)
		usage 0
		;;
	esac

	# İlk parametre profil adı
	local profile_name="$1"
	shift

		# Varsayılan değerler
		local window_class=""
		local window_title=""
		local helium_args=()
		local kill_profile=false
		local incognito_mode=false
		# Niri/Hyprland'da workspace rule'ların düzgün çalışması için default: ayrı instance
		local separate_mode="auto"
		local pid_file=""

	# Parametreleri güvenli şekilde işle
		while [[ $# -gt 0 ]]; do
			case "${1:-}" in
			--class=*) window_class="${1#*=}" ;;
			--class)
				shift
				if [[ -z "${1:-}" ]]; then
					log "ERROR" "--class parametresi bir değer bekliyor"
					exit 1
				fi
				window_class="$1"
				;;
			--title=*) window_title="${1#*=}" ;;
			--title)
				shift
				if [[ -z "${1:-}" ]]; then
					log "ERROR" "--title parametresi bir değer bekliyor"
					exit 1
				fi
				window_title="$1"
				;;
			--separate) separate_mode="true" ;;
			--no-separate) separate_mode="false" ;;
			--pid-file=*) pid_file="${1#*=}" ;;
			--pid-file)
				shift
				if [[ -z "${1:-}" ]]; then
					log "ERROR" "--pid-file parametresi bir değer bekliyor"
					exit 1
				fi
				pid_file="$1"
				;;
			--proxy=*)
				IFS=':' read -r PROXY_HOST PROXY_PORT <<<"${1#*=}"
				PROXY_ENABLED=true
				;;
		--proxy) PROXY_ENABLED=true ;;
		--proxy-host=*)
			PROXY_HOST="${1#*=}"
			PROXY_ENABLED=true
			;;
		--proxy-port=*)
			PROXY_PORT="${1#*=}"
			PROXY_ENABLED=true
			;;
		--proxy-type=*)
			PROXY_TYPE="${1#*=}"
			PROXY_ENABLED=true
			;;
		--kill-profile) kill_profile=true ;;
		--incognito) incognito_mode=true ;;
		--help | -h) usage 0 ;;
		*)
			if [[ -n "${1:-}" ]]; then
				helium_args+=("$1")
			fi
			;;
		esac
		shift
	done

	# Proxy profili kontrolü
	if [[ "$profile_name" == "Proxy" && "$PROXY_ENABLED" == false ]]; then
		PROXY_ENABLED=true
		log "INFO" "Proxy profili seçildi, proxy otomatik etkinleştirildi"
	fi

	# Profili doğrula ve kaynağını çöz (default + isolated Local State'lerde ara)
	local profile_key=""
	local profile_source_dir=""
	local profile_local_state=""
	local resolved=""
	if ! resolved="$(resolve_profile_source "$profile_name")"; then
		log "ERROR" "Profil bulunamadı: $profile_name"
		list_profiles
		exit 1
	fi
	profile_local_state="${resolved%%$'\t'*}"
	profile_key="${resolved#*$'\t'}"
	profile_source_dir="$(dirname "$profile_local_state")"

	# Profil örneklerini kapat
	if $kill_profile; then
		kill_profile_helium "$profile_key"
	fi

		# Pencere ayarları
		[[ -z "$window_class" ]] && window_class="$profile_name"
		[[ -z "$window_title" ]] && window_title="$profile_name Browser"

	# İnkognito modu
	if $incognito_mode; then
		window_title="$window_title (İnkognito)"
		window_class="${window_class}_incognito"
		log "INFO" "İnkognito modu etkinleştirildi"
	fi

		# separate_mode auto: Wayland (niri/hyprland) için aç, X11 için kapalı
		if [[ "$separate_mode" == "auto" ]]; then
			if [[ -n "${WAYLAND_DISPLAY:-}" ]] || [[ "${XDG_SESSION_TYPE:-}" == "wayland" ]]; then
				separate_mode="true"
			else
				separate_mode="false"
			fi
		fi

		# Komut oluştur
			local cmd=("$HELIUM_CMD")
			if [[ "$separate_mode" == "true" ]]; then
				local isolated_dir="${ISOLATED_ROOT}/${window_class}"
				ensure_isolated_userdata "$isolated_dir" "$profile_source_dir"
				ensure_isolated_profile_dir "$isolated_dir" "$profile_key" "$profile_source_dir"

				cmd+=("--user-data-dir=$isolated_dir")
			else
				# Default user-data-dir ile çalışırken de marker dosyasını güncel tut.
				ensure_widevine_marker "$profile_source_dir"
			fi
			cmd+=("--profile-directory=$profile_key")

	# İnkognito modu
	if $incognito_mode; then
		cmd+=("--incognito")
	else
		cmd+=("${DEFAULT_FLAGS[@]}")
	fi

	# Özel bayraklar
	if [[ -n "${CUSTOM_FLAGS:-}" ]]; then
		# shellcheck disable=SC2086
		cmd+=($CUSTOM_FLAGS)
	fi

	# Proxy ayarları
	if [[ "$PROXY_ENABLED" == true ]]; then
		log "INFO" "Proxy etkinleştiriliyor: ${PROXY_TYPE}://${PROXY_HOST}:${PROXY_PORT}"
		cmd+=("--proxy-server=${PROXY_TYPE}://${PROXY_HOST}:${PROXY_PORT}")
		cmd+=("--host-resolver-rules=MAP * ~NOTFOUND, EXCLUDE ${PROXY_HOST}")
		cmd+=("--proxy-bypass-list=<local>")
	fi

	# Pencere ayarları
	cmd+=("--class=$window_class")
	cmd+=("--name=$window_class")
	cmd+=("--window-name=$window_title")

	# Ek parametreler
	[[ ${#helium_args[@]} -gt 0 ]] && cmd+=("${helium_args[@]}")

	# Debug bilgisi (sadece debug modunda göster)
	[[ "${DEBUG_MODE:-false}" == "true" ]] && debug "Komut: ${cmd[*]}"
	log "INFO" "Kullanılan Helium komutu: $HELIUM_CMD"

	# Helium'i başlat
	log "SUCCESS" "Helium başlatılıyor: $profile_name"

	# Önce komutu test et
	if [[ "$HELIUM_CMD" == */* ]]; then
		if [[ ! -x "$HELIUM_CMD" ]]; then
			log "ERROR" "Helium komutu bulunamadı: $HELIUM_CMD"
			exit 1
		fi
	elif ! command -v "$HELIUM_CMD" &>/dev/null; then
		log "ERROR" "Helium komutu bulunamadı: $HELIUM_CMD"
		exit 1
	fi

	# Komutu çalıştır ve çıktısını yakala
	if "${cmd[@]}" >/dev/null 2> >(tail -n 20 >&2) & then
		local helium_pid=$!
		log "INFO" "Helium başlatıldı (PID: $helium_pid)"

		if [[ -n "$pid_file" ]]; then
			mkdir -p "$(dirname "$pid_file")" 2>/dev/null || true
			printf '%s\n' "$helium_pid" >"$pid_file" 2>/dev/null || true
		fi

		# Helium'in başlamasını bekle ve daha iyi kontrol et
		sleep 1

		# Helium'in hala çalışıp çalışmadığını kontrol et
		if kill -0 "$helium_pid" 2>/dev/null; then
			log "SUCCESS" "Helium başarıyla çalışıyor (PID: $helium_pid)"
		else
			# Process çoktan başka bir PID'ye geçmiş olabilir (normal)
			log "SUCCESS" "Helium başlatıldı"
		fi
	else
		log "ERROR" "Helium başlatılamadı"

		# Hata durumunda komutu debug için tekrar çalıştır
		log "INFO" "Debug için komut tekrar çalıştırılıyor..."
		"${cmd[@]}" 2>&1 | head -5 | while read -r line; do
			log "ERROR" "$line"
		done
		return 1
	fi
}

# Scripti çalıştır
main "$@"
