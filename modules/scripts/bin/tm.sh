#!/usr/bin/env bash
# ==============================================================================
# Script: tm.sh
# Description: Comprehensive Tmux management tool for sessions, layouts, buffers, and plugins
# Usage: tm.sh <module> [command] [parameters]
# ==============================================================================
#######################################
#
# tm.sh - Birleşik Tmux Yönetim Aracı
#
# Version: 2.0.0
# Date: 2025-10-30
# Author: Kenan Pelit
# Description: Comprehensive Tmux management, session, layouts, buffers, plugins, and more
#
# Bu script birçok tmux yardımcı programını tek bir komut satırı aracında birleştirir:
#
# - Oturum Yönetimi:
#   - Oturum oluştur, bağlan, sonlandır, listele
#   - Akıllı oturum adlandırma (git/dizin tabanlı)
#   - Layout şablonları (1-5 panel düzeni)
#
# - Pano ve Buffer Yönetimi:
#   - Tmux buffer yönetimi
#   - Sistem panosu entegrasyonu
#   - Sık kullanılan komutlar için hızlandırma
#
# - Eklenti Yönetimi:
#   - Eklenti kurulumu ve güncelleme
#   - TPM entegrasyonu
#
# - Yapılandırma:
#   - Yapılandırma yedekleme ve geri yükleme
#   - Terminal entegrasyonu (kitty/alacritty)
#
# License: MIT
#
#######################################

# Katı hata yönetimi
set -euo pipefail

# Script metadata
readonly SCRIPT_NAME="${0##*/}"

# Resolve script path once (portable)
resolve_script_path() {
	local src="${BASH_SOURCE[0]:-$0}"
	if command -v realpath >/dev/null 2>&1; then
		realpath "$src"
	elif readlink -f "$src" >/dev/null 2>&1; then
		readlink -f "$src"
	else
		printf '%s\n' "$src"
	fi
}

cmd_exists() { command -v "$1" >/dev/null 2>&1; }

require_cmd() {
	local name="$1"
	if ! cmd_exists "$name"; then
		error "Komut bulunamadı: $name"
		exit 1
	fi
}

# Global yapılandırma
readonly VERSION="2.0.0"
readonly CONFIG_DIR="${HOME}/.config/tmux"
readonly PLUGIN_DIR="${CONFIG_DIR}/plugins"
readonly FZF_DIR="${CONFIG_DIR}/fzf"
readonly DEFAULT_SESSION="KENP"
readonly BACKUP_GLOB="tmux_backup_*.tar.gz"
readonly HISTORY_LIMIT=100
readonly SOCKET_DIR="/tmp/tmux-${UID}"
SCRIPT_PATH="$(resolve_script_path)"
TMUX_BIN="$(command -v tmux 2>/dev/null || true)"
readonly SCRIPT_PATH TMUX_BIN

tmux_cmd() {
	"${TMUX_BIN:-tmux}" "$@"
}

# Soft tmux çağrısı — başarısız olursa DEBUG=1 modunda log'lar, ama
# script'i durdurmaz. set -e altında "|| true" sessizce yutuyordu.
tmux_try() {
	if ! tmux_cmd "$@" 2>/dev/null; then
		debug "tmux başarısız: $*"
		return 1
	fi
}

# Dizinler gerekli olduğunda lazy oluşturulur (eskiden tepe-seviye
# mkdir vardı; "tm.sh version" / "help" çağrılarında bile dosya
# sistemine yazıyordu). Use-site'lar ensure_dir ile yaratır.
ensure_dir() {
	local d="$1"
	[[ -d "$d" ]] && return 0
	if ! mkdir -p "$d" 2>/dev/null; then
		error "Dizin oluşturulamadı: $d"
		return 1
	fi
}

# Renk tanımlamaları — TTY değilse veya NO_COLOR set ise devre dışı.
# log() stdout, error() stderr'e yazıyor; her ikisi de TTY ise renk aç.
if [[ -t 1 && -t 2 && -z "${NO_COLOR:-}" ]]; then
	RED='\033[0;31m'
	GREEN='\033[0;32m'
	YELLOW='\033[1;33m'
	BLUE='\033[0;34m'
	MAGENTA='\033[0;35m'
	CYAN='\033[0;36m'
	NC='\033[0m'
else
	RED='' GREEN='' YELLOW='' BLUE='' MAGENTA='' CYAN='' NC=''
fi
readonly RED GREEN YELLOW BLUE MAGENTA CYAN NC

# Mesaj fonksiyonları - timestamp eklendi
log() {
	local level="$1"
	local color="$2"
	shift 2 || true

	local ts
	if ! printf -v ts '%(%H:%M:%S)T' -1 2>/dev/null; then
		# Fallback (very old bash): external `date`.
		ts="$(date +%H:%M:%S)"
	fi

	printf '%b[%s]%b %b[%s]%b %s\n' "$color" "$ts" "$NC" "$color" "$level" "$NC" "$*"
}

info() {
	log "INFO" "$GREEN" "$*"
}

warn() {
	log "WARN" "$YELLOW" "$*"
}

error() {
	log "ERROR" "$RED" "$*" >&2
}

status() {
	log "STATUS" "$BLUE" "$*"
}

success() {
	log "SUCCESS" "$GREEN" "$*"
}

debug() {
	if [[ "${DEBUG:-0}" == "1" ]]; then
		log "DEBUG" "$MAGENTA" "$*" >&2
	fi
}

# Catppuccin Mocha fzf tema argümanları — scope'lu (eskiden global
# FZF_DEFAULT_OPTS export ediliyordu, kullanıcının normal fzf
# ayarlarını script ömrünce eziyordu). fzf_themed() üzerinden kullan.
_TM_FZF_THEME=(
	-e -i
	--info=inline
	--layout=reverse
	--border=rounded
	--margin=1
	--padding=1
	--ansi
	--pointer=▶
	--marker=✓
	--color='bg+:#313244,bg:#1e1e2e,spinner:#f5e0dc,hl:#f38ba8'
	--color='fg:#cdd6f4,header:#89b4fa,info:#cba6f7,pointer:#f5e0dc'
	--color='marker:#a6e3a1,fg+:#cdd6f4,prompt:#cba6f7,hl+:#f38ba8'
	--tiebreak=index
)

# Tema-aware fzf çağrı yardımcısı. Tema önce, kullanıcı argümanları
# sonra — böylece site-spesifik --preview / --bind override edebilir.
fzf_themed() {
	local prompt="${1:-Tmux} ❯ "
	local header="${2:-CTRL-R: Yenile | ESC: Çık}"
	shift 2 || true
	fzf "${_TM_FZF_THEME[@]}" --prompt="$prompt" --header="$header" "$@"
}

#--------------------------------------
# HELPER FUNCTIONS
#--------------------------------------

# Tmux kurulu mu kontrol et
check_tmux() {
	if [[ -z "${TMUX_BIN:-}" ]]; then
		error "Tmux kurulu değil. Lütfen önce tmux'u kurun."
		exit 1
	fi
}

# Tmux oturumu içinde miyiz
is_in_tmux() {
	[[ -n "${TMUX:-}" ]]
}

# Oturum var mı kontrolü (tam eşleşme)
has_session_exact() {
	check_tmux
	local name="${1:-}"
	[[ -z "$name" ]] && return 1

	# Prefer `has-session` (fast). Use `=name` for exact match when supported.
	if tmux_cmd has-session -t "=${name}" 2>/dev/null; then
		return 0
	fi

	# Fallback for older tmux: exact match via list + grep.
	tmux_cmd list-sessions -F "#{session_name}" 2>/dev/null | grep -Fxq -- "$name"
}

# Oturum adı doğrulaması - daha geniş karakter desteği
validate_session_name() {
	local name="$1"

	if [[ -z "$name" ]]; then
		error "Oturum adı boş olamaz."
		return 1
	fi

	if [[ "$name" =~ [^a-zA-Z0-9_.-] ]]; then
		error "Geçersiz oturum adı: '$name'. Sadece harf, rakam, tire, alt çizgi ve nokta kullanabilirsiniz."
		return 1
	fi

	if [[ "${#name}" -gt 50 ]]; then
		error "Oturum adı çok uzun (maksimum 50 karakter)."
		return 1
	fi

	return 0
}

# Mevcut dizin veya git reposuna göre oturum adı al
get_session_name() {
	local dir_name="${PWD##*/}"

	if command -v git >/dev/null 2>&1 && git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
		local top
		top="$(git rev-parse --show-toplevel 2>/dev/null || true)"
		if [[ -n "$top" ]]; then
			echo "${top##*/}"
			return 0
		fi
	fi

	echo "$dir_name"
}

# Oturuma bağlan veya zaten bağlıysa değiştir
attach_or_switch() {
	local session_name="$1"

	if ! has_session_exact "$session_name"; then
		error "Oturum '$session_name' bulunamadı."
		return 1
	fi

	if is_in_tmux; then
		if ! tmux_cmd switch-client -t "$session_name" 2>/dev/null; then
			error "'$session_name' oturumuna geçilemedi."
			return 1
		fi
	else
		if ! tmux_cmd attach-session -t "$session_name" 2>/dev/null; then
			error "'$session_name' oturumuna bağlanılamadı."
			return 1
		fi
	fi

	success "Oturum '$session_name' aktif."
}

# Belirli bir mod için gerekli bağımlılıkları kontrol et
check_requirements() {
	local mode="$1"
	local req_failed=0

	case "$mode" in
	"session")
		check_tmux
		;;
	"buffer")
		check_tmux
		if ! is_in_tmux; then
			error "Tmux oturumunda değilsiniz. Lütfen tmux içinde çalıştırın."
			req_failed=1
		fi
		;;
	"clipboard")
		# Clipboard backends:
		# - cliphist + wl-clipboard: fzf üzerinden geçmiş seçimi + silme
		# - clipse: kendi TUI/clipboard history ekranını açar (cliphist olmadan da çalışır)
		#
		# Manuel seçim:
		#   TM_CLIPBOARD_BACKEND=cliphist tm.sh clip
		#   TM_CLIPBOARD_BACKEND=clipse   tm.sh clip
		local backend="${TM_CLIPBOARD_BACKEND:-auto}"

		# Auto-detect best available backend.
		if [[ "$backend" == "auto" ]]; then
			if command -v cliphist &>/dev/null && command -v wl-copy &>/dev/null; then
				backend="cliphist"
			elif command -v clipse &>/dev/null; then
				backend="clipse"
			else
				backend="cliphist"
			fi
		fi

		case "$backend" in
		cliphist)
			if ! command -v cliphist &>/dev/null; then
				error "cliphist kurulu değil!"
				info "Gerekli: cliphist + wl-clipboard (wl-copy/wl-paste)"
				req_failed=1
			fi
			if ! command -v wl-copy &>/dev/null; then
				error "wl-clipboard kurulu değil!"
				info "Gerekli: wl-clipboard (wl-copy/wl-paste)"
				req_failed=1
			fi
			;;
		clipse)
			if ! command -v clipse &>/dev/null; then
				error "clipse kurulu değil!"
				info "Alternatif olarak cliphist + wl-clipboard kullanabilirsin."
				req_failed=1
			fi
			;;
		*)
			error "Bilinmeyen clipboard backend: $backend"
			req_failed=1
			;;
		esac

		if [[ "$req_failed" -ne 0 ]]; then
			info "Çözümler:"
			info "  - (Önerilen) cliphist + wl-clipboard (wl-copy/wl-paste)"
			info "  - Alternatif: clipse"
			info "Backend seçimi:"
			info "  TM_CLIPBOARD_BACKEND=cliphist tm.sh clip"
			info "  TM_CLIPBOARD_BACKEND=clipse   tm.sh clip"
		fi
		;;
	"plugin")
		check_tmux
		if ! command -v git &>/dev/null; then
			error "git kurulu değil!"
			req_failed=1
		fi
		;;
	"speed")
		if ! command -v fzf >/dev/null 2>&1; then
			error "fzf kurulu değil!"
			req_failed=1
		fi
		if ! command -v find >/dev/null 2>&1; then
			error "find komutu bulunamadı (coreutils/findutils)!"
			req_failed=1
		fi
		if [[ ! -d "$FZF_DIR" ]]; then
			warn "Komut dizini bulunamadı: $FZF_DIR"
			info "Dizin oluşturuluyor..."
			mkdir -p "$FZF_DIR"
		fi
		;;
	"all")
		check_tmux
		for cmd in fzf git; do
			if ! command -v "$cmd" &>/dev/null; then
				error "$cmd kurulu değil!"
				req_failed=1
			fi
		done
		;;
	esac

	return "$req_failed"
}

# Terminal tespiti - genişletilmiş destek
detect_terminal() {
	if [[ -n "${KITTY_WINDOW_ID:-}" ]] || command -v kitty >/dev/null 2>&1; then
		echo "kitty"
	elif command -v alacritty >/dev/null 2>&1; then
		echo "alacritty"
	elif command -v foot >/dev/null 2>&1; then
		echo "foot"
	else
		echo "x-terminal-emulator"
	fi
}

# Tmux soket dosyalarını temizle
clean_sockets() {
	warn "Soket dosyaları temizleniyor..."

	if [[ -d "$SOCKET_DIR" ]]; then
		for socket in "$SOCKET_DIR"/*; do
			if [[ -S "$socket" ]]; then
				rm -f "$socket" 2>/dev/null || true
				debug "Soket silindi: $socket"
			fi
		done
	fi

	tmux_cmd kill-server >/dev/null 2>&1 || true
	sleep 1
	success "Soketler temizlendi"
}

# Tmux sürüm kontrolü
check_tmux_version() {
	local required_version="3.0"
	local current_version_str cur_major cur_minor req_major req_minor

	if ! command -v tmux_cmd >/dev/null 2>&1; then
		return 0
	fi

	current_version_str="$(tmux_cmd -V 2>/dev/null || true)"

	if [[ "$current_version_str" =~ ([0-9]+)\\.([0-9]+) ]]; then
		cur_major="${BASH_REMATCH[1]}"
		cur_minor="${BASH_REMATCH[2]}"
	else
		return 0
	fi

	# Basit sürüm karşılaştırması (bc gerektirmeyen)
	req_major="${required_version%%.*}"
	req_minor="${required_version##*.}"

	if [[ "$cur_major" -lt "$req_major" ]] ||
		[[ "$cur_major" -eq "$req_major" && "$cur_minor" -lt "$req_minor" ]]; then
		warn "Tmux sürümü eski: ${cur_major}.${cur_minor} (Önerilen: $required_version+)"
	fi
}

#--------------------------------------
# SESSION MANAGEMENT
#--------------------------------------

# Tüm tmux oturumlarını listele - gelişmiş format
list_sessions() {
	check_tmux

	local sessions
	if ! sessions="$(tmux_cmd list-sessions -F "#{session_name}: #{session_windows} pencere, #{session_attached} bağlı#{?session_grouped, (gruplu),}" 2>/dev/null)"; then
		warn "Aktif oturum yok"
		return 0
	fi

	info "Mevcut oturumlar:"
	while IFS= read -r line; do
		echo "  • $line"
	done <<<"$sessions"
}

# Tmux oturumunu sonlandır
kill_session() {
	local session_name="$1"

	if ! has_session_exact "$session_name"; then
		error "Oturum '$session_name' bulunamadı"
		return 1
	fi

	# Eğer şu an bu oturumun içindeysek uyar
	if is_in_tmux && [[ "$(tmux_cmd display-message -p '#S')" == "$session_name" ]]; then
		warn "Şu anda bu oturumun içindesiniz!"
		read -p "Yine de sonlandırmak istiyor musunuz? (e/H): " -n 1 -r
		echo
		if [[ ! $REPLY =~ ^[Ee]$ ]]; then
			info "İptal edildi"
			return 0
		fi
	fi

	if tmux_cmd kill-session -t "$session_name" 2>/dev/null; then
		success "Oturum '$session_name' sonlandırıldı"
	else
		warn "İlk denemede sonlandırılamadı; soket temizliği deneniyor..."
		clean_sockets
		if tmux_cmd kill-session -t "$session_name" 2>/dev/null; then
			success "Oturum '$session_name' sonlandırıldı (soket temizliği sonrası)"
		else
			error "Oturum '$session_name' sonlandırılamadı"
			return 1
		fi
	fi
}

# Yeni oturum oluştur veya mevcut oturuma bağlan
create_session() {
	local session_name="$1"
	local layout="${2:-}"

	if ! validate_session_name "$session_name"; then
		return 1
	fi

	if has_session_exact "$session_name"; then
		info "Oturum '$session_name' zaten var, bağlanıyor..."

		# Oturum zaten başka yerde bağlıysa ve biz tmux içinde değilsek yeni pencere oluştur
		if ! is_in_tmux && tmux_cmd list-sessions 2>/dev/null | grep -q "^${session_name}: .* (attached)$"; then
			warn "Oturum başka yerde bağlı, yeni pencere oluşturuluyor..."
			local window_count
			window_count=$(tmux_cmd list-windows -t "$session_name" 2>/dev/null | wc -l)
			debug "Mevcut pencere sayısı: $window_count"
			tmux_cmd new-window -t "$session_name" 2>/dev/null || warn "Yeni pencere oluşturulamadı"
		fi

		attach_or_switch "$session_name"
	else
		info "Yeni oturum oluşturuluyor: '$session_name'..."

		if ! tmux_cmd new-session -d -s "$session_name" 2>/dev/null; then
			warn "Oturum oluşturulamadı, soket temizliği deneniyor..."
			clean_sockets

			if ! tmux_cmd new-session -d -s "$session_name" 2>/dev/null; then
				error "Temizlikten sonra bile oturum oluşturulamadı!"
				return 1
			fi
		fi

		# Layout belirtilmişse uygula
		if [[ -n "$layout" ]]; then
			create_layout "$session_name" "$layout"
		fi

		success "Oturum oluşturuldu, bağlanıyor..."
		attach_or_switch "$session_name"
	fi
}

# Yeni terminal penceresinde oturum aç
open_session_in_terminal() {
	local terminal_type="$1"
	local session_name="$2"
	local layout="${3:-1}"
	local class_name="tmux-$session_name"
	local title="Tmux: $session_name"
	local script_path

	script_path="${SCRIPT_PATH}"

	case "$terminal_type" in
	kitty)
		if ! cmd_exists kitty; then
			error "Kitty terminal kurulu değil!"
			return 1
		fi
		kitty --class="$class_name" \
			--title="$title" \
			--directory="$PWD" \
			-e bash -c "$script_path session create \"$session_name\" $layout" &
		;;
	alacritty)
		if ! cmd_exists alacritty; then
			error "Alacritty terminal kurulu değil!"
			return 1
		fi
		alacritty --class "$class_name" \
			--title "$title" \
			--working-directory "$PWD" \
			-e bash -c "$script_path session create \"$session_name\" $layout" &
		;;
	*)
		error "Desteklenmeyen terminal türü: $terminal_type"
		info "Desteklenen terminaller: kitty, alacritty"
		return 1
		;;
	esac

	success "Terminal başlatıldı: '$session_name'"
}

#--------------------------------------
# LAYOUT FUNCTIONS
#--------------------------------------

# Çeşitli tmux düzenleri oluştur
create_layout() {
	local session_name="$1"
	local layout_num="$2"
	local shell_cmd="${SHELL:-/bin/zsh} -l"
	# Layout pencerelerinin başlangıç dizini — env ile override edilebilir.
	local cwd="${TM_LAYOUT_CWD:-$HOME}"

	if ! has_session_exact "$session_name"; then
		error "Oturum '$session_name' bulunamadı."
		return 1
	fi

	info "Oturum '$session_name' için düzen $layout_num oluşturuluyor..."

	case "$layout_num" in
	1)
		# Tek panel düzeni (sadece yeni pencere, split yok — placeholder)
		tmux_try new-window -t "$session_name" -n 'kenp' -c "$cwd"
		tmux_try select-pane -t 1
		;;
	2)
		# İki panel düzeni (dikey bölme - %80 üst)
		tmux_try new-window -t "$session_name" -n 'kenp' -c "$cwd"
		tmux_try split-window -v -l 80% -c "$cwd"
		tmux_try select-pane -t 2
		;;
	3)
		# Üç panel L-şekilli düzen
		tmux_try new-window -t "$session_name" -n 'kenp' -c "$cwd"
		tmux_try split-window -h -l 80% -c "$cwd"
		tmux_try select-pane -t 2
		tmux_try split-window -v -l 85% -c "$cwd"
		tmux_try select-pane -t 3
		;;
	4)
		# Dört panel grid düzeni
		tmux_try new-window -t "$session_name" -n 'kenp' -c "$cwd"
		tmux_try split-window -h -l 80% -c "$cwd"
		tmux_try split-window -v -l 80% -c "$cwd"
		tmux_try select-pane -t 1
		tmux_try split-window -v -l 80% -c "$cwd"
		tmux_try select-pane -t 4
		;;
	5)
		# Beş panel düzeni
		tmux_try new-window -t "$session_name" -n 'kenp' -c "$cwd"
		tmux_try split-window -h -l 70% -c "$cwd"
		tmux_try split-window -h -l 50% -c "$cwd"
		tmux_try select-pane -t 1
		tmux_try split-window -v -l 50% -c "$cwd"
		tmux_try select-pane -t 2
		tmux_try split-window -v -l 50% -c "$cwd"
		tmux_try select-pane -t 5
		;;
	*)
		error "Geçersiz düzen numarası: $layout_num (1-5 arası olmalı)"
		return 1
		;;
	esac

	success "Düzen $layout_num oluşturuldu"
}

#--------------------------------------
# BUFFER MANAGEMENT
#--------------------------------------

# Buffer modunu işle - geliştirilmiş
handle_buffer_mode() {
	if ! check_requirements "buffer"; then
		return 1
	fi

	local buffer_count
	buffer_count=$(tmux_cmd list-buffers 2>/dev/null | wc -l)

	if [[ "$buffer_count" -eq 0 ]]; then
		warn "Hiç buffer yok"
		return 0
	fi

	info "Buffer sayısı: $buffer_count"

	local selected
	selected=$(tmux_cmd list-buffers -F "#{buffer_name}: #{buffer_sample}" 2>/dev/null |
		fzf_themed "Buffer" "ENTER: Kopyala | CTRL-D: Sil | ESC: Çık" \
			--delimiter=': ' \
			--preview 'tmux show-buffer -b {1}' \
			--preview-window=up:70%:wrap \
			--bind 'ctrl-d:execute(tmux delete-buffer -b {1})+reload(tmux list-buffers -F "#{buffer_name}: #{buffer_sample}")' \
			--header-lines=0)

	if [[ -n "$selected" ]]; then
		local buffer_name
		buffer_name="${selected%%:*}"

		if tmux_cmd show-buffer -b "$buffer_name" | wl-copy 2>/dev/null; then
			success "Buffer kopyalandı: $buffer_name"
		else
			error "Buffer kopyalanamadı"
			return 1
		fi
	fi
}

#--------------------------------------
# CLIPBOARD MANAGEMENT
#--------------------------------------

# Pano modunu işle
handle_clipboard_mode() {
	if ! check_requirements "clipboard"; then
		return 1
	fi

	local backend="${TM_CLIPBOARD_BACKEND:-auto}"
	if [[ "$backend" == "auto" ]]; then
		if command -v cliphist &>/dev/null && command -v wl-copy &>/dev/null; then
			backend="cliphist"
		elif command -v clipse &>/dev/null; then
			backend="clipse"
		else
			backend="cliphist"
		fi
	fi

	if [[ "$backend" == "cliphist" ]]; then
		local selected
		selected=$(cliphist list |
			fzf_themed "Clipboard" "ENTER: Yapıştır | CTRL-D: Sil | ESC: Çık" \
				--preview 'echo {} | cliphist decode' \
				--preview-window=up:70%:wrap \
				--bind 'ctrl-d:execute(echo {} | cliphist delete)+reload(cliphist list)')

		if [[ -n "$selected" ]]; then
			if echo "$selected" | cliphist decode | wl-copy 2>/dev/null; then
				success "Panoya kopyalandı"
			else
				error "Panoya kopyalanamadı"
				return 1
			fi
		fi
		return 0
	fi

	if [[ "$backend" == "clipse" ]]; then
		# Clipse kendi içinde geçmişi listeler, seçer, pin/sil işlemlerini yapar.
		# tm.sh sadece bu arayüzü açar.
		info "Clipse açılıyor (clipboard history)..."
		clipse
		return $?
	fi

	error "Bilinmeyen clipboard backend: $backend"
	return 1
}

#--------------------------------------
# PLUGIN MANAGEMENT
#--------------------------------------

# Eklenti kur
install_plugin() {
	local plugin_name="$1"
	local repo_url="$2"
	local plugin_path="${PLUGIN_DIR}/${plugin_name}"

	ensure_dir "$PLUGIN_DIR" || return 1

	if [[ -d "$plugin_path" ]]; then
		warn "Eklenti zaten kurulu: $plugin_name"
		read -p "Güncelleme yapmak ister misiniz? (e/H): " -n 1 -r
		echo
		if [[ $REPLY =~ ^[Ee]$ ]]; then
			info "Eklenti güncelleniyor: $plugin_name"
			if git -C "$plugin_path" pull 2>/dev/null; then
				success "Eklenti güncellendi: $plugin_name"
			else
				error "Eklenti güncellenemedi: $plugin_name"
				return 1
			fi
		fi
		return 0
	fi

	info "Eklenti kuruluyor: $plugin_name"
	if git clone "$repo_url" "$plugin_path" 2>/dev/null; then
		success "Eklenti kuruldu: $plugin_name"
	else
		error "Eklenti kurulamadı: $plugin_name"
		return 1
	fi
}

# Kurulu eklentileri listele
list_plugins() {
		if [[ ! -d "$PLUGIN_DIR" ]] || ! compgen -G "${PLUGIN_DIR}/*" >/dev/null; then
			warn "Kurulu eklenti yok"
			return 0
		fi

		info "Kurulu eklentiler:"
		for plugin in "$PLUGIN_DIR"/*; do
			if [[ -d "$plugin" ]]; then
				local plugin_name
				plugin_name="${plugin##*/}"
				local last_update=""

			if [[ -d "$plugin/.git" ]]; then
				last_update=$(git -C "$plugin" log -1 --format="%ar" 2>/dev/null || echo "bilinmiyor")
				echo "  • $plugin_name (son güncelleme: $last_update)"
			else
				echo "  • $plugin_name"
			fi
		fi
	done
}

# Tüm önerilen eklentileri kur
install_all_plugins() {
	info "Önerilen eklentiler kuruluyor..."

	local plugins=(
		"tpm:https://github.com/tmux-plugins/tpm"
		"tmux-sensible:https://github.com/tmux-plugins/tmux-sensible"
		"tmux-resurrect:https://github.com/tmux-plugins/tmux-resurrect"
		"tmux-continuum:https://github.com/tmux-plugins/tmux-continuum"
		"tmux-yank:https://github.com/tmux-plugins/tmux-yank"
		"tmux-copycat:https://github.com/tmux-plugins/tmux-copycat"
	)

	local failed=0
	for plugin_info in "${plugins[@]}"; do
		local name="${plugin_info%%:*}"
		local url="${plugin_info##*:}"

		if ! install_plugin "$name" "$url"; then
			((failed++))
		fi
	done

	if [[ "$failed" -eq 0 ]]; then
		success "Tüm eklentiler başarıyla kuruldu"
	else
		warn "$failed eklenti kurulamadı"
	fi
}

#--------------------------------------
# SPEED MODE (Command Shortcuts)
#--------------------------------------

# Hız modunu işle - hızlı komut çalıştırma için
# Speed mode v2 — category-aware launcher with pin + recency.
#
# State files (under $FZF_DIR):
#   .fzf_cache  — usage log (one base per execution, capped at HISTORY_LIMIT)
#   .fzf_pins   — pinned bases (rendered with ⭐ at top of list)
#
# In-picker hotkeys:
#   ↵      run selected script
#   ⌃p     toggle pin (rewrites .fzf_pins, list reloads in place)
#   ⌃e     edit script in $EDITOR
#   ⌃o     open $FZF_DIR in yazi
handle_speed_mode() {
	if ! check_requirements "speed"; then
		return 1
	fi

	ensure_dir "$FZF_DIR" || return 1
	local cache_file="${FZF_DIR}/.fzf_cache"
	local pins_file="${FZF_DIR}/.fzf_pins"
	touch "$cache_file" "$pins_file"

	local total ssh_count vpn_count
	total="$(find "$FZF_DIR" -maxdepth 1 -type f -name '_*' 2>/dev/null | wc -l | tr -d '[:space:]')"
	ssh_count="$(find "$FZF_DIR" -maxdepth 1 -type f -name '_ssh*' 2>/dev/null | wc -l | tr -d '[:space:]')"
	vpn_count="$(find "$FZF_DIR" -maxdepth 1 -type f -name '_ssh*vpn*' 2>/dev/null | wc -l | tr -d '[:space:]')"

	if [[ "$total" -eq 0 ]]; then
		warn "Hiç speed komutu bulunamadı"
		info "Örnek komutlar oluşturmak için: $SCRIPT_NAME speed init"
		return 0
	fi

	debug "Toplam: $total | SSH: $ssh_count | VPN: $vpn_count"

	# Dump helpers to a temp file so they're callable from fzf --bind sub-shells.
	local helpers
	helpers="$(mktemp -t tm-speed.XXXXXX)"
	# RETURN trap fires after fzf exits, keeping helpers alive for binds.
	trap 'rm -f "$helpers"' RETURN

	{
		printf "FZF_DIR=%q\n" "$FZF_DIR"
		printf "cache_file=%q\n" "$cache_file"
		printf "pins_file=%q\n" "$pins_file"
		cat <<'BODY'

# Categorize by leading-_ stripped basename → "<icon> <LABEL>" (padded to 5).
speed_category() {
	case "$1" in
		ssh_*vpn*)              printf '%s' '󰒃 VPN  ' ;;
		ssh_*podman*)           printf '%s' ' POD  ' ;;
		ssh_*)                  printf '%s' '󰣀 SSH  ' ;;
		*-history)              printf '%s' '󰋖 HIST ' ;;
		translate_*)            printf '%s' '󰊿 I18N ' ;;
		emoji|compose|zinger|snippets)
								printf '%s' '󰅍 CLIP ' ;;
		ipwebtv|ytfzf)          printf '%s' '󰕧 MEDIA' ;;
		playerctl|pulseaudio|volume_mute)
								printf '%s' '󰕾 AUDIO' ;;
		anote|notes)            printf '%s' '󰠮 NOTE ' ;;
		yazi_locate)            printf '%s' '󰉋 FILE ' ;;
		wpaperctl)              printf '%s' '󰸉 WALL ' ;;
		*window-switcher)       printf '%s' '󰓩 TMUX ' ;;
		fman)                   printf '%s' '󰈙 DOCS ' ;;
		applauncher)            printf '%s' '󰀻 APP  ' ;;
		fkill)                  printf '%s' '󰜺 KILL ' ;;
		trash)                  printf '%s' '󰩹 TRASH' ;;
		calculator)             printf '%s' '󰪚 MATH ' ;;
		*)                      printf '%s' ' MISC ' ;;
	esac
}

# Strip "_" prefix; split "name,--.dotted.description" → "name|description".
speed_display_name() {
	local f="$1" base desc name d
	base="${f%%,*}"
	desc=""; [[ "$f" == *","* ]] && desc="${f#*,}"
	name="${base#_}"; name="${name//_/ }"; name="${name//./ }"
	d="${desc//./ }"; d="${d# }"; d="${d#-- }"
	printf '%s|%s' "$name" "$d"
}

resolve_script_for_base() {
	local base="$1" m
	shopt -s nullglob
	local -a matches=("$FZF_DIR/${base},"* "$FZF_DIR/${base}")
	shopt -u nullglob
	for m in "${matches[@]}"; do
		[[ -f "$m" ]] && { printf '%s' "${m##*/}"; return; }
	done
}

format_row() {
	local fname="$1" base cat name desc
	base="${fname%%,*}"
	cat="$(speed_category "${base#_}")"
	IFS='|' read -r name desc <<<"$(speed_display_name "$fname")"
	if [[ -n "$desc" ]]; then
		printf '%s  %-24s · %s' "$cat" "$name" "$desc"
	else
		printf '%s  %s' "$cat" "$name"
	fi
}

toggle_pin() {
	local base="${1%%,*}"
	if grep -Fxq -- "$base" "$pins_file" 2>/dev/null; then
		grep -Fxv -- "$base" "$pins_file" >"${pins_file}.tmp" 2>/dev/null || :
		mv "${pins_file}.tmp" "$pins_file" 2>/dev/null || :
	else
		printf '%s\n' "$base" >>"$pins_file"
	fi
}

# Score = frequency + recency bonus (latest cache lines weight more).
# Output: <filename>\t<icon> <CAT>  <name>  · <desc>
# Pinned first (alpha), then by score desc, then alpha.
build_speed_list() {
	local -A pinned=() score=()
	local p
	while IFS= read -r p; do
		[[ -n "$p" ]] && pinned["$p"]=1
	done <"$pins_file"

	local -a recent=()
	mapfile -t recent <"$cache_file"
	local n=${#recent[@]} i base bonus
	for ((i = 0; i < n; i++)); do
		base="${recent[$i]}"
		[[ -n "$base" ]] || continue
		bonus=$(((i + 1) * 10 / (n + 1))) # 0..10, newer entries higher
		score["$base"]=$((${score["$base"]:-0} + 1 + bonus))
	done

	# Pinned section (sorted alpha by base name)
	if ((${#pinned[@]} > 0)); then
		local b fname
		for b in "${!pinned[@]}"; do
			printf '%s\n' "$b"
		done | sort | while IFS= read -r b; do
			fname="$(resolve_script_for_base "$b")"
			[[ -n "$fname" ]] || continue
			printf '%s\t⭐ %s\n' "$fname" "$(format_row "$fname")"
		done
	fi

	# Non-pinned: score desc, then alpha
	local s fname
	while IFS= read -r fname; do
		base="${fname%%,*}"
		[[ -n "${pinned[$base]:-}" ]] && continue
		s="${score[$base]:-0}"
		# Pad score reversed so sort puts highest first; tie-break by filename.
		printf '%010d\t%s\n' "$((9999999999 - s))" "$fname"
	done < <(find "$FZF_DIR" -maxdepth 1 -type f -name '_*' -printf '%f\n' 2>/dev/null) \
		| sort \
		| while IFS=$'\t' read -r _ fname; do
			printf '%s\t  %s\n' "$fname" "$(format_row "$fname")"
		done
}
BODY
	} >"$helpers"

	local selection
	selection="$(
		bash -c ". '$helpers'; build_speed_list" \
			| fzf_themed "Speed" "Total $total · SSH $ssh_count · VPN $vpn_count │ ↵ run · ⌃p pin · ⌃e edit · ⌃o files · esc" \
				--delimiter=$'\t' \
				--with-nth=2.. \
				--no-sort \
				--bind "ctrl-p:execute-silent(bash -c \". '$helpers'; toggle_pin {1}\")+reload(bash -c \". '$helpers'; build_speed_list\")" \
				--bind "ctrl-e:execute(\${EDITOR:-nvim} '$FZF_DIR'/{1})+reload(bash -c \". '$helpers'; build_speed_list\")" \
				--bind "ctrl-o:execute(yazi '$FZF_DIR')"
	)" || {
		info "İptal edildi"
		return 0
	}

	if [[ -z "$selection" ]]; then
		info "İptal edildi"
		return 0
	fi

	local selected="${selection%%$'\t'*}"
	[[ -z "$selected" ]] && {
		info "İptal edildi"
		return 0
	}

	# Record usage (base only, for stable scoring across renamed descriptions).
	local selected_base="${selected%%,*}"
	printf '%s\n' "$selected_base" >>"$cache_file"
	if [[ "$(wc -l <"$cache_file")" -gt "$HISTORY_LIMIT" ]]; then
		tail -n "$HISTORY_LIMIT" "$cache_file" >"${cache_file}.tmp" \
			&& mv "${cache_file}.tmp" "$cache_file"
	fi

	local script_path="${FZF_DIR}/${selected}"
	if [[ -f "$script_path" ]]; then
		success "Çalıştırılıyor: ${selected}"
		[[ -x "$script_path" ]] || chmod +x "$script_path" 2>/dev/null || true
		if "$script_path"; then
			success "Komut tamamlandı"
		else
			error "Komut hatası"
			return 1
		fi
	else
		error "Script bulunamadı: ${selected}"
		return 1
	fi
}

# Örnek speed komut dosyası oluştur
create_sample_speed_commands() {
	local sample_dir="$FZF_DIR"

	info "Örnek speed komutları oluşturuluyor: $sample_dir"

	# SSH komutları
	cat >"${sample_dir}/_ssh.server1" <<'EOF'
#!/usr/bin/env bash
# SSH to server1
ssh user@server1.example.com
EOF

	cat >"${sample_dir}/_ssh.server2" <<'EOF'
#!/usr/bin/env bash
# SSH to server2
ssh user@server2.example.com
EOF

	# Tmux komutları
	cat >"${sample_dir}/_tmux.list" <<'EOF'
#!/usr/bin/env bash
# List all tmux sessions
tmux list-sessions
EOF

	cat >"${sample_dir}/_tmux.kill-all" <<'EOF'
#!/usr/bin/env bash
# Kill all tmux sessions
read -p "Tüm tmux oturumlarını sonlandırmak istediğinize emin misiniz? (e/H): " -n 1 -r
echo
if [[ $REPLY =~ ^[Ee]$ ]]; then
    tmux kill-server
    echo "Tüm oturumlar sonlandırıldı"
fi
EOF

	cat >"${sample_dir}/_tmux.attach" <<'EOF'
#!/usr/bin/env bash
# Attach to last tmux session
tmux attach || tmux new-session
EOF

	# Git komutları
	cat >"${sample_dir}/_git.status" <<'EOF'
#!/usr/bin/env bash
# Git status with color
git status
EOF

	cat >"${sample_dir}/_git.pull" <<'EOF'
#!/usr/bin/env bash
# Git pull with rebase
git pull --rebase
EOF

	cat >"${sample_dir}/_git.push" <<'EOF'
#!/usr/bin/env bash
# Git push current branch
current_branch=$(git branch --show-current)
git push origin "$current_branch"
EOF

	# System komutları
	cat >"${sample_dir}/_system.update" <<'EOF'
#!/usr/bin/env bash
# System update (Arch Linux)
if command -v yay &>/dev/null; then
    yay -Syu
elif command -v pacman &>/dev/null; then
    sudo pacman -Syu
fi
EOF

	cat >"${sample_dir}/_system.clean" <<'EOF'
#!/usr/bin/env bash
# Clean package cache
if command -v yay &>/dev/null; then
    yay -Sc
elif command -v pacman &>/dev/null; then
    sudo pacman -Sc
fi
EOF

	# Docker komutları
	cat >"${sample_dir}/_docker.ps" <<'EOF'
#!/usr/bin/env bash
# List running containers
docker ps
EOF

	cat >"${sample_dir}/_docker.clean" <<'EOF'
#!/usr/bin/env bash
# Clean docker system
docker system prune -af
EOF

	# Tüm dosyaları çalıştırılabilir yap
		chmod +x "${sample_dir}"/_* 2>/dev/null

		success "Örnek komutlar oluşturuldu: $sample_dir"
		local sample_count=0
		shopt -s nullglob
		local -a sample_files=("${sample_dir}"/_*)
		sample_count="${#sample_files[@]}"
		shopt -u nullglob
		info "Toplam ${sample_count} örnek komut"
	}

# Speed komutlarını listele
list_speed_commands() {
	if [[ ! -d "$FZF_DIR" ]]; then
		warn "Speed komut dizini bulunamadı: $FZF_DIR"
		return 1
	fi

	local total
	total=$(find "$FZF_DIR" -maxdepth 1 -type f -name '_*' 2>/dev/null | wc -l)

		if [[ "$total" -eq 0 ]]; then
			warn "Hiç speed komutu bulunamadı"
			info "Örnek komutlar oluşturmak için: $SCRIPT_NAME speed init"
			return 0
		fi

	info "Speed Komutları (Toplam: $total)"
	echo

	# Kategorilere göre grupla
	for category in ssh tmux git docker system; do
		local count
		count=$(find "$FZF_DIR" -maxdepth 1 -type f -name "_${category}*" 2>/dev/null | wc -l)

		if [[ "$count" -gt 0 ]]; then
				echo -e "${YELLOW}${category^^}:${NC} ($count komut)"
				find "$FZF_DIR" -maxdepth 1 -type f -name "_${category}*" 2>/dev/null |
					while read -r file; do
						local name desc
						name="${file##*/}"
						name="${name#_}"

						local -a header=()
						mapfile -t -n 2 header <"$file"
						desc="${header[1]#\# }"
						echo "  • $name - $desc"
					done
				echo
			fi
		done

		# Diğer komutlar
		local other_count
		other_count=$(find "$FZF_DIR" -maxdepth 1 -type f -name '_*' 2>/dev/null |
			grep -vcE '_(ssh|tmux|git|docker|system)')

	if [[ "$other_count" -gt 0 ]]; then
		echo -e "${YELLOW}DİĞER:${NC} ($other_count komut)"
			find "$FZF_DIR" -maxdepth 1 -type f -name '_*' 2>/dev/null |
				grep -v -E '_(ssh|tmux|git|docker|system)' |
				while read -r file; do
					local name desc
					name="${file##*/}"
					name="${name#_}"

					local -a header=()
					mapfile -t -n 2 header <"$file"
					desc="${header[1]#\# }"
					echo "  • $name - $desc"
				done
			echo
		fi
	}

# Speed komutu ekle
add_speed_command() {
	local name="$1"
	local command="$2"

	if [[ -z "$name" ]] || [[ -z "$command" ]]; then
		error "Kullanım: tm.sh speed add <isim> <komut>"
		return 1
	fi

	local file="${FZF_DIR}/_${name}"

	if [[ -f "$file" ]]; then
		warn "Komut zaten var: $name"
		read -p "Üzerine yazmak ister misiniz? (e/H): " -n 1 -r
		echo
		if [[ ! $REPLY =~ ^[Ee]$ ]]; then
			info "İptal edildi"
			return 0
		fi
	fi

	cat >"$file" <<EOF
#!/usr/bin/env bash
# $name
$command
EOF

	chmod +x "$file"
	success "Speed komutu eklendi: $name"
}

# Speed komutu sil
remove_speed_command() {
	local name="$1"

	if [[ -z "$name" ]]; then
		error "Kullanım: tm.sh speed remove <isim>"
		return 1
	fi

	local file
	file=$(find "$FZF_DIR" -maxdepth 1 -type f -name "_${name}*" 2>/dev/null | head -1)

	if [[ -z "$file" ]]; then
		error "Komut bulunamadı: $name"
		return 1
	fi

		warn "Komut silinecek: ${file##*/}"
		read -p "Emin misiniz? (e/H): " -n 1 -r
		echo

	if [[ $REPLY =~ ^[Ee]$ ]]; then
		rm -f "$file"
		success "Komut silindi: $name"
	else
		info "İptal edildi"
	fi
}

# Speed komutu düzenle
edit_speed_command() {
	local name="$1"

	if [[ -z "$name" ]]; then
		error "Kullanım: tm.sh speed edit <isim>"
		return 1
	fi

	local file
	file=$(find "$FZF_DIR" -maxdepth 1 -type f -name "_${name}*" 2>/dev/null | head -1)

	if [[ -z "$file" ]]; then
		error "Komut bulunamadı: $name"
		return 1
	fi

	"${EDITOR:-vim}" "$file"
}

# Speed dizinini aç
open_speed_dir() {
	if [[ ! -d "$FZF_DIR" ]]; then
		warn "Speed dizini bulunamadı, oluşturuluyor..."
		mkdir -p "$FZF_DIR"
	fi

	cd "$FZF_DIR" || return 1
	info "Speed dizini: $FZF_DIR"

	if [[ -n "$SHELL" ]]; then
		"$SHELL"
	else
		bash
	fi
}

#--------------------------------------
# CONFIGURATION BACKUP/RESTORE
#--------------------------------------

# Yapılandırmayı yedekle
backup_config() {
	local stamp
	if ! printf -v stamp '%(%Y%m%d_%H%M%S)T' -1 2>/dev/null; then
		stamp="$(date +%Y%m%d_%H%M%S)"
	fi

	local backup_path="${HOME}/tmux_backup_${stamp}.tar.gz"

	info "Tmux yapılandırması yedekleniyor..."

	if tar czf "$backup_path" -C "$HOME" \
		".config/tmux" \
		".cache/tmux-manager" 2>/dev/null; then
		success "Yedek oluşturuldu: $backup_path"

		local size
		size=$(du -h "$backup_path" | cut -f1)
		info "Yedek boyutu: $size"
	else
		error "Yedek oluşturulamadı"
		return 1
	fi
}

# Yapılandırmayı geri yükle
restore_config() {
	local backup_path="${1:-}"

	if [[ -z "$backup_path" ]]; then
		local -a backups=()
		mapfile -t backups < <(compgen -G "${HOME}/${BACKUP_GLOB}" || true)

		if [[ "${#backups[@]}" -eq 0 ]]; then
			backup_path=""
		else
			local latest=""
			local latest_mtime=0

			for f in "${backups[@]}"; do
				[[ -f "$f" ]] || continue

				local mtime
				mtime="$(stat -c %Y -- "$f" 2>/dev/null || stat -f %m "$f" 2>/dev/null || printf '0')"

				if [[ -z "$latest" ]] || [[ "$mtime" -gt "$latest_mtime" ]]; then
					latest="$f"
					latest_mtime="$mtime"
				fi
			done

			backup_path="$latest"
		fi
	fi

	if [[ ! -f "$backup_path" ]]; then
		error "Yedek dosyası bulunamadı: ${backup_path:-"(bulunamadı)"}"
		info "Mevcut yedekler:"
		local -a backups=()
		mapfile -t backups < <(compgen -G "${HOME}/${BACKUP_GLOB}" || true)
		for f in "${backups[@]}"; do
			echo "  • ${f##*/}"
		done
		return 1
	fi

	warn "Mevcut yapılandırma üzerine yazılacak!"
	read -p "Devam etmek istiyor musunuz? (e/H): " -n 1 -r
	echo

	if [[ ! $REPLY =~ ^[Ee]$ ]]; then
		info "İptal edildi"
		return 0
	fi

	info "Yapılandırma geri yükleniyor..."

	if tar xzf "$backup_path" -C "$HOME" 2>/dev/null; then
		success "Yapılandırma geri yüklendi"
	else
		error "Yapılandırma geri yüklenemedi"
		return 1
	fi
}

#--------------------------------------
# KENP SESSION MODE
#--------------------------------------

# anka, açılışta bu oturumu snapshot'tan geri yükleyecek mi? Yalnızca şu üç koşul
# birden sağlanırsa "evet" döner ve bekleriz:
#   1) @anka-restore-on-start açık (boş değer = anka varsayılanı 'on'),
#   2) bir 'last' snapshot mevcut,
#   3) snapshot bu oturumu içeriyor.
# Aksi halde (restore kapalı / snapshot yok / oturum snapshot'ta yok) "hayır"
# döner; böylece autorestore OFF senaryosunda HİÇ beklemeyiz, KENP'i kenp_session_mode
# 4. adımda anında kendimiz kurarız.
anka_restore_pending() {
	local session_name="$1"

	local ros
	ros="$(tmux_cmd show-options -gqv @anka-restore-on-start 2>/dev/null || true)"
	case "$ros" in
	"" | on | 1 | true | yes) ;; # açık (boş = anka varsayılanı)
	*) return 1 ;;               # kapalı → bekleme yok
	esac

	local dir
	dir="$(tmux_cmd show-options -gqv @anka-dir 2>/dev/null || true)"
	[[ -z "$dir" ]] && dir="${XDG_DATA_HOME:-$HOME/.local/share}/tmux/anka"
	dir="${dir/#\~/$HOME}"

	local snap="${dir}/snapshots/last/snapshot.json"
	[[ -f "$snap" ]] || return 1

	grep -Fq "\"name\": \"${session_name}\"" "$snap" 2>/dev/null
}

# KENP geliştirme oturumu (tek-sahip kurgu).
#
# Eski hâl KENP'i doğrudan `new-session -d -s KENP` ile yaratıyordu; bu komut
# server'ı başlatınca anka'nın restore-on-start'ı arka planda AYNI KENP'i kurmaya
# başlıyor, ikisi çakışıp "duplicate session: KENP" hatası veriyor ve tm (dolayısıyla
# kitty penceresi) kapanıyordu — tmux ise arkada yaşamaya devam ettiği için kullanıcı
# 2. kez başlatmak zorunda kalıyordu. Çözüm: KENP'in tek sahibi belli olsun.
#   - autorestore AÇIK + snapshot'ta KENP varsa → sahibi anka; biz sadece bekleyip bağlanırız.
#   - autorestore KAPALI / snapshot yok / KENP yoksa → sahibi tm; beklemeden kendimiz kurarız.
kenp_session_mode() {
	local session_name="${1:-$DEFAULT_SESSION}"

	if ! validate_session_name "$session_name"; then
		return 1
	fi

	info "KENP oturumu başlatılıyor: $session_name"

	# 1) Zaten varsa (server açık + anka restore etmiş ya da önceki çalışmadan) bağlan.
	if has_session_exact "$session_name"; then
		attach_or_switch "$session_name"
		return $?
	fi

	# 2) Yoksa önce server'ı başlat. start-server idempotenttir: server kapalıysa onu
	#    ayağa kaldırır ve böylece anka restore-on-start'ı tetikler. KENP'i burada
	#    YARATMIYORUZ — autostart ile new-session yarışını baştan ortadan kaldırmak için.
	tmux_cmd start-server 2>/dev/null || true

	# 3) anka bu oturumu snapshot'tan getirecekse, gelmesini bekle (en fazla ~5 sn).
	#    Bekleme yalnızca restore gerçekten beklenirken yapılır; OFF senaryosunda
	#    anka_restore_pending "hayır" döndüğü için bu blok tümüyle atlanır (gecikme yok).
	if anka_restore_pending "$session_name"; then
		info "anka snapshot'tan '$session_name' geri yükleniyor, bekleniyor..."
		local waited=0
		while ((waited < 50)); do
			has_session_exact "$session_name" && break
			sleep 0.1
			waited=$((waited + 1))
		done
	fi

	# 4) Hâlâ yoksa (restore kapalı / snapshot'ta yok / zaman aşımı) kendimiz kuralım.
	#    -A: anka tam bu an oturumu kurmuş olsa bile "duplicate session" hatası vermez;
	#    var olana bağlanır, yoksa oluşturur. Çakışma artık imkânsız.
	if ! has_session_exact "$session_name"; then
		if ! tmux_cmd new-session -A -d -s "$session_name" -n 'terminal' 2>/dev/null; then
			error "'$session_name' oturumu oluşturulamadı"
			return 1
		fi
		success "'$session_name' oturumu hazır"
	fi

	# 5) Bağlan.
	attach_or_switch "$session_name"
}

#--------------------------------------
# HELP FUNCTIONS
#--------------------------------------

# Oturum yardımı
show_session_help() {
	cat <<EOF
$(echo -e "${GREEN}")Oturum Yönetimi$(echo -e "${NC}")

Kullanım: $SCRIPT_NAME session <komut> [parametreler]

Komutlar:
    create <ad> [düzen]  Yeni oturum oluştur veya mevcut oturuma bağlan
    list                 Tüm oturumları listele
    kill <ad>            Oturumu sonlandır
    attach <ad>          Oturuma bağlan
    layout <ad> <no>     Belirtilen düzeni uygula (1-5)
    term <tip> <ad> [düzen]  Yeni terminalde oturum aç (kitty/alacritty)

Düzenler:
    1: Tek panel
    2: İki panel (dikey bölme, %80 üst)
    3: Üç panel (L-şekilli düzen)
    4: Dört panel (grid düzeni)
    5: Beş panel (özel düzen)

Örnekler:
    $SCRIPT_NAME session create myproject 3
    $SCRIPT_NAME session list
    $SCRIPT_NAME session kill myproject
    $SCRIPT_NAME session term kitty dev 2
    $SCRIPT_NAME session term alacritty myproject 3

Notlar:
    • Parametre verilmezse, mevcut dizin adıyla oturum oluşturulur
    • Git repo'dayken, repo adı oturum adı olarak kullanılır
    • Oturum adları sadece harf, rakam, tire, nokta ve alt çizgi içerebilir
EOF
}

# Buffer yardımı
show_buffer_help() {
	cat <<EOF
$(echo -e "${GREEN}")Buffer Yönetimi$(echo -e "${NC}")

Kullanım: $SCRIPT_NAME buffer [komut]

Komutlar:
    show    İnteraktif buffer tarayıcısı (varsayılan)
    list    Buffer'ları listele

Kısayollar (buffer modunda):
    ENTER:   Buffer'ı panoya kopyala
    CTRL-D:  Buffer'ı sil
    CTRL-J/K: Preview yukarı/aşağı
    ESC:     Çık

Not: Buffer modu sadece tmux oturumu içinde çalışır
EOF
}

# Pano yardımı
show_clipboard_help() {
	cat <<EOF
$(echo -e "${GREEN}")Pano Yönetimi$(echo -e "${NC}")

Kullanım: $SCRIPT_NAME clip

İnteraktif pano geçmişi tarayıcısı.

Kısayollar:
    ENTER:   Öğeyi panoya kopyala
    CTRL-D:  Öğeyi sil
    CTRL-J/K: Preview yukarı/aşağı
    ESC:     Çık

Backend'ler:
    • cliphist + wl-clipboard  (varsayılan, fzf arayüzü)
    • clipse                  (alternatif, kendi TUI arayüzü)

Backend seçimi:
    TM_CLIPBOARD_BACKEND=cliphist $SCRIPT_NAME clip
    TM_CLIPBOARD_BACKEND=clipse   $SCRIPT_NAME clip

Kurulum (Arch):
    yay -S cliphist wl-clipboard
EOF
}

# Eklenti yardımı
show_plugin_help() {
	cat <<EOF
$(echo -e "${GREEN}")Eklenti Yönetimi$(echo -e "${NC}")

Kullanım: $SCRIPT_NAME plugin <komut> [parametreler]

Komutlar:
    install <ad> <url>  Eklenti kur
    list                Kurulu eklentileri listele
    all                 Tüm önerilen eklentileri kur

Önerilen Eklentiler:
    • tpm              - Tmux Plugin Manager
    • tmux-sensible    - Temel ayarlar
    • tmux-resurrect   - Oturum kaydetme
    • tmux-continuum   - Otomatik kaydetme
    • tmux-yank        - Gelişmiş kopyalama
    • tmux-copycat     - Regex arama

Örnekler:
    $SCRIPT_NAME plugin all
    $SCRIPT_NAME plugin list
    $SCRIPT_NAME plugin install custom https://github.com/user/plugin

Not: TPM kullanıyorsanız, eklentileri tmux.conf'da da tanımlamalısınız
EOF
}

# Hız modu yardımı
show_speed_help() {
	cat <<EOF
$(echo -e "${GREEN}")Komut Hızlandırma (Speed Mode)$(echo -e "${NC}")

Kullanım: $SCRIPT_NAME speed [komut] [parametreler]

Komutlar:
    show              İnteraktif komut seçici (varsayılan)
    list              Tüm speed komutlarını listele
    init              Örnek speed komutları oluştur
    add <isim> <cmd>  Yeni speed komutu ekle
    remove <isim>     Speed komutunu sil
    edit <isim>       Speed komutunu düzenle
    dir               Speed dizinini aç

Speed Komut Formatı:
    Dosya adı: _komut veya _komut,açıklama (örn: _ssh_agu_hpc,--.create.new.window)
    Konum: ~/.config/tmux/fzf/
    İçerik: Çalıştırılabilir bash scripti

Özellikler:
    • Sık kullanılan komutlar ⭐ ile işaretlenir
    • Kullanım geçmişi otomatik kaydedilir
    • Kategorilere göre gruplandırma
    • Hızlı arama ve filtreleme

Kategoriler:
    _ssh.*      SSH bağlantıları
    _tmux.*     Tmux komutları
    _git.*      Git işlemleri
    _docker.*   Docker komutları
    _system.*   Sistem komutları

Örnekler:
	# İnteraktif mod
    $SCRIPT_NAME speed
    
	# Komutları listele
    $SCRIPT_NAME speed list
    
	# Örnek komutlar oluştur
    $SCRIPT_NAME speed init
    
	# Yeni komut ekle
    $SCRIPT_NAME speed add git.status "git status"
    
	# Komut düzenle
    $SCRIPT_NAME speed edit ssh.server1
    
	# Komut sil
    $SCRIPT_NAME speed remove git.status
    
	# Speed dizinini aç
    $SCRIPT_NAME speed dir

Manuel Komut Oluşturma:
    1. Dosya oluştur:
       ~/.config/tmux/fzf/_kategori.isim
    
    2. İçeriğini yaz:
       #!/usr/bin/env bash
       # Komut açıklaması
       komutunuz buraya
    
    3. Çalıştırılabilir yap:
       chmod +x ~/.config/tmux/fzf/_kategori.isim

Kısayollar (speed modunda):
    ENTER:    Komutu çalıştır
    ESC:      Çık

İpuçları:
    • Komut adları kısa ve açıklayıcı olmalı
    • Kategorileri tutarlı kullanın
    • Tehlikeli komutlar için onay ekleyin
    • Sık kullanılan komutlar otomatik öne çıkar
    • Cache dosyası: ~/.config/tmux/fzf/.fzf_cache (fspeed ile uyumlu)

Not: Speed modu ~/.config/tmux/fzf/ dizinindeki _* dosyalarını kullanır
EOF
}

# Yapılandırma yardımı
show_backup_help() {
	cat <<EOF
$(echo -e "${GREEN}")Yapılandırma Yönetimi$(echo -e "${NC}")

Kullanım: $SCRIPT_NAME config <komut>

Komutlar:
    backup   Tmux yapılandırmasını yedekle
    restore  Yapılandırmayı geri yükle

Yedeklenen Dizinler:
    • ~/.config/tmux
    • ~/.cache/tmux-manager

Yedek Dosyası:
    ~/tmux_backup_YYYYMMDD_HHMMSS.tar.gz

Örnekler:
    $SCRIPT_NAME config backup
    $SCRIPT_NAME config restore

Not: Geri yükleme işlemi mevcut yapılandırmanın üzerine yazar
EOF
}

# KENP yardımı
show_kenp_help() {
	cat <<EOF
$(echo -e "${GREEN}")KENP Geliştirme Oturumu$(echo -e "${NC}")

Kullanım: $SCRIPT_NAME kenp [oturum_adı]

Basit ve hızlı tmux oturumu oluşturur.

Pencere:
    terminal - Tek basit terminal penceresi

Özellikler:
    • Minimalist yaklaşım - tek pencere
    • Anında kullanıma hazır
    • Layout'ları manuel oluşturabilirsiniz
    • Hızlı başlangıç

Layout Oluşturma:
    $SCRIPT_NAME s layout KENP 3    # Layout 3 uygula
    $SCRIPT_NAME s layout KENP 4    # Layout 4 uygula

Örnekler:
    $SCRIPT_NAME kenp          # 'KENP' adıyla oturum
    $SCRIPT_NAME kenp dev      # 'dev' adıyla oturum
    $SCRIPT_NAME               # KENP oturumu (varsayılan)

Not: Parametre verilmezse 'KENP' adıyla oturum oluşturulur
EOF
}

# TMX yardımı (legacy uyumluluk)
show_tmx_help() {
	cat <<EOF
$(echo -e "${GREEN}")TMX Modu (Legacy Uyumluluk)$(echo -e "${NC}")

Kullanım: $SCRIPT_NAME tmx [seçenek] [parametreler]

Seçenekler:
    -h, --help              Bu yardımı göster
    -l, --list              Oturumları listele
    -k, --kill <ad>         Oturumu sonlandır
    -n, --new <ad>          Yeni oturum oluştur
    -a, --attach <ad>       Oturuma bağlan
    -d, --detach            Oturumdan ayrıl
    -t, --terminal <tip> <ad> [düzen]  Terminalde oturum aç
    --layout <no>           Düzen uygula (1-5)

Örnekler:
    $SCRIPT_NAME tmx -l
    $SCRIPT_NAME tmx -n myproject
    $SCRIPT_NAME tmx -t kitty dev 3
    $SCRIPT_NAME tmx --layout 2

Not: Yeni projeler için 'session' modunu kullanın
EOF
}

# Ana yardım
show_help() {
	cat <<EOF
$(echo -e "${CYAN}")╔════════════════════════════════════════════════════════════════╗
║         tm.sh v${VERSION} - Tmux Yönetim Aracı               ║
╚════════════════════════════════════════════════════════════════╝$(echo -e "${NC}")

$(echo -e "${GREEN}")Kullanım:$(echo -e "${NC}") $SCRIPT_NAME <modül> [komut] [parametreler]

$(echo -e "${GREEN}")Modüller:$(echo -e "${NC}")
    $(echo -e "${YELLOW}")session$(echo -e "${NC}")    Oturum ve düzen yönetimi
    $(echo -e "${YELLOW}")buffer$(echo -e "${NC}")     Buffer yönetimi ve navigasyon
    $(echo -e "${YELLOW}")clip$(echo -e "${NC}")       Pano geçmişi ve yönetimi
    $(echo -e "${YELLOW}")plugin$(echo -e "${NC}")     Eklenti kurulumu ve yönetimi
    $(echo -e "${YELLOW}")speed$(echo -e "${NC}")      Komut hızlandırma ve favoriler
    $(echo -e "${YELLOW}")config$(echo -e "${NC}")     Yapılandırma yedekleme ve geri yükleme
    $(echo -e "${YELLOW}")kenp$(echo -e "${NC}")       KENP geliştirme oturumu başlat
    $(echo -e "${YELLOW}")tmx$(echo -e "${NC}")        Legacy tmux komutları (eski uyumluluk)
    $(echo -e "${YELLOW}")help$(echo -e "${NC}")       Yardım mesajlarını göster

$(echo -e "${GREEN}")Hızlı Başlangıç:$(echo -e "${NC}")
    $SCRIPT_NAME                           # KENP oturumu (varsayılan)
    $SCRIPT_NAME session create proje 3    # 3 nolu düzenle oturum
    $SCRIPT_NAME buffer                    # Buffer tarayıcı
    $SCRIPT_NAME clip                      # Pano geçmişi
    $SCRIPT_NAME plugin all                # Tüm eklentileri kur
    $SCRIPT_NAME speed                     # Hızlı komut çalıştırıcı

$(echo -e "${GREEN}")Örnekler:$(echo -e "${NC}")
	# Oturum yönetimi
    $SCRIPT_NAME s create myproject        # Oturum oluştur
    $SCRIPT_NAME s list                    # Oturumları listele
    $SCRIPT_NAME s kill myproject          # Oturumu sonlandır
    
	# Düzen kullanımı
    $SCRIPT_NAME s create dev 3            # 3 nolu düzenle oturum
    $SCRIPT_NAME s layout dev 4            # Mevcut oturuma düzen 4 uygula
    
	# Terminal entegrasyonu
    $SCRIPT_NAME s term kitty dev 2        # Kitty'de 2 nolu düzenle oturum
    
	# Speed komutları
    $SCRIPT_NAME speed                     # İnteraktif hızlı komutlar
    $SCRIPT_NAME speed init                # Örnek komutlar oluştur
    $SCRIPT_NAME speed list                # Tüm komutları listele

$(echo -e "${GREEN}")Detaylı Yardım:$(echo -e "${NC}")
    $SCRIPT_NAME help <modül>              # Modül-spesifik yardım

$(echo -e "${GREEN}")Ortam Değişkenleri:$(echo -e "${NC}")
    DEBUG=1                                    # Debug modunu etkinleştir
    EDITOR=vim                                 # Varsayılan editör

$(echo -e "${GREEN}")Gereksinimler:$(echo -e "${NC}")
    $(echo -e "${CYAN}")Temel:$(echo -e "${NC}") tmux, bash, fzf
    $(echo -e "${CYAN}")İsteğe Bağlı:$(echo -e "${NC}") git, cliphist, wl-clipboard, kitty/alacritty

$(echo -e "${GREEN}")Yapılandırma:$(echo -e "${NC}")
    $(echo -e "${CYAN}")Ana Dizin:$(echo -e "${NC}")       ~/.config/tmux
    $(echo -e "${CYAN}")Eklentiler:$(echo -e "${NC}")      ~/.config/tmux/plugins
    $(echo -e "${CYAN}")Önbellek:$(echo -e "${NC}")        ~/.cache/tmux-manager
    $(echo -e "${CYAN}")Komutlar:$(echo -e "${NC}")        ~/.config/tmux/fzf/_*

$(echo -e "${GREEN}")Yazar:$(echo -e "${NC}") Kenan Pelit
$(echo -e "${GREEN}")Lisans:$(echo -e "${NC}") MIT
$(echo -e "${GREEN}")Sürüm:$(echo -e "${NC}") ${VERSION}

	Daha fazla bilgi: $SCRIPT_NAME help <modül>
EOF
}

# Yardım komutlarını işle
process_help_commands() {
	local module="${1:-}"

	case "$module" in
	"session" | "s")
		show_session_help
		;;
	"buffer" | "b")
		show_buffer_help
		;;
	"clip" | "c")
		show_clipboard_help
		;;
	"plugin" | "p")
		show_plugin_help
		;;
	"speed" | "cmd")
		show_speed_help
		;;
	"config" | "cfg")
		show_backup_help
		;;
	"kenp" | "k")
		show_kenp_help
		;;
	"tmx")
		show_tmx_help
		;;
	*)
		show_help
		;;
	esac
}

#--------------------------------------
# COMMAND PROCESSORS
#--------------------------------------

# Oturum komutlarını işle
process_session_commands() {
	local command="${1:-}"
	shift 2>/dev/null || true

	case "$command" in
	"create" | "c")
		local session_name="${1:-$(get_session_name)}"
		local layout="${2:-}"
		create_session "$session_name" "$layout"
		;;
	"list" | "l" | "ls")
		list_sessions
		;;
	"kill" | "k")
		if [[ -z "${1:-}" ]]; then
			error "Oturum adı belirtilmedi"
			return 1
		fi
		kill_session "$1"
		;;
	"attach" | "a")
		if [[ -z "${1:-}" ]]; then
			error "Oturum adı belirtilmedi"
			return 1
		fi
		if has_session_exact "$1"; then
			attach_or_switch "$1"
		else
			error "Oturum '$1' bulunamadı"
			return 1
		fi
		;;
	"layout" | "lo")
		if [[ -z "${1:-}" ]] || [[ -z "${2:-}" ]]; then
			error "Oturum adı ve düzen numarası gerekli"
			return 1
		fi
		create_layout "$1" "$2"
		;;
	"term" | "t")
		if [[ -z "${1:-}" ]] || [[ -z "${2:-}" ]]; then
			error "Terminal türü ve oturum adı gerekli"
			info "Desteklenen terminaller: kitty, alacritty"
			return 1
		fi
		local layout="${3:-1}"
		open_session_in_terminal "$1" "$2" "$layout"
		;;
	*)
		error "Bilinmeyen oturum komutu: $command"
		show_session_help
		return 1
		;;
	esac
}

# Buffer komutlarını işle
process_buffer_commands() {
	local command="${1:-show}"
	shift 2>/dev/null || true

	case "$command" in
	"list" | "l" | "ls")
		if ! check_requirements "buffer"; then
			return 1
		fi
		tmux_cmd list-buffers
		;;
	"show" | "s" | "")
		handle_buffer_mode
		;;
	*)
		error "Bilinmeyen buffer komutu: $command"
		show_buffer_help
		return 1
		;;
	esac
}

# Pano komutlarını işle
process_clipboard_commands() {
	local command="${1:-show}"
	shift 2>/dev/null || true

	case "$command" in
	"show" | "s" | "")
		handle_clipboard_mode
		;;
	*)
		error "Bilinmeyen pano komutu: $command"
		show_clipboard_help
		return 1
		;;
	esac
}

# Eklenti komutlarını işle
process_plugin_commands() {
	local command="${1:-}"
	shift 2>/dev/null || true

	case "$command" in
	"install" | "i")
		if [[ -z "${1:-}" ]] || [[ -z "${2:-}" ]]; then
			error "Eklenti adı ve repository gerekli"
			show_plugin_help
			return 1
		fi
		install_plugin "$1" "$2"
		;;
	"list" | "l" | "ls")
		list_plugins
		;;
	"all" | "a")
		install_all_plugins
		;;
	*)
		error "Bilinmeyen eklenti komutu: $command"
		show_plugin_help
		return 1
		;;
	esac
}

# Hız komutlarını işle
process_speed_commands() {
	local command="${1:-show}"
	shift 2>/dev/null || true

	case "$command" in
	"show" | "s" | "")
		handle_speed_mode
		;;
	"list" | "l" | "ls")
		list_speed_commands
		;;
	"init" | "i")
		create_sample_speed_commands
		;;
	"add" | "a")
		if [[ -z "${1:-}" ]] || [[ -z "${2:-}" ]]; then
			error "Kullanım: speed add <isim> <komut>"
			return 1
		fi
		add_speed_command "$1" "$2"
		;;
	"remove" | "rm" | "r")
		if [[ -z "${1:-}" ]]; then
			error "Kullanım: speed remove <isim>"
			return 1
		fi
		remove_speed_command "$1"
		;;
	"edit" | "e")
		if [[ -z "${1:-}" ]]; then
			error "Kullanım: speed edit <isim>"
			return 1
		fi
		edit_speed_command "$1"
		;;
	"dir" | "d" | "open" | "o")
		open_speed_dir
		;;
	*)
		error "Bilinmeyen hız komutu: $command"
		show_speed_help
		return 1
		;;
	esac
}

# Yapılandırma komutlarını işle
process_config_commands() {
	local command="${1:-}"
	shift 2>/dev/null || true

	case "$command" in
	"backup" | "b")
		backup_config
		;;
	"restore" | "r")
		restore_config
		;;
	*)
		error "Bilinmeyen config komutu: $command"
		show_backup_help
		return 1
		;;
	esac
}

# TMX komutlarını işle (legacy uyumluluk)
process_tmx_commands() {
	local command="${1:-}"
	shift 2>/dev/null || true

	case "$command" in
	"-h" | "--help" | "help")
		show_tmx_help
		;;
	"-l" | "--list" | "list")
		list_sessions
		;;
	"-k" | "--kill" | "kill")
		if [[ -z "${1:-}" ]]; then
			error "Oturum adı belirtilmedi"
			return 1
		fi
		kill_session "$1"
		;;
	"-n" | "--new" | "new")
		if [[ -z "${1:-}" ]]; then
			error "Oturum adı belirtilmedi"
			return 1
		fi
		create_session "$1"
		;;
	"-t" | "--terminal" | "term")
		if [[ -z "${1:-}" ]] || [[ -z "${2:-}" ]]; then
			error "Terminal türü ve oturum adı belirtilmelidir"
			return 1
		fi
		local layout="${3:-1}"
		open_session_in_terminal "$1" "$2" "$layout"
		;;
	"-d" | "--detach" | "detach")
		tmux_cmd detach-client
		;;
	"-a" | "--attach" | "attach")
		if [[ -z "${1:-}" ]]; then
			error "Oturum adı belirtilmedi"
			return 1
		fi
		if has_session_exact "$1"; then
			attach_or_switch "$1"
		else
			error "Oturum '$1' bulunamadı"
			return 1
		fi
		;;
	"--layout" | "layout")
		if [[ -z "${1:-}" ]]; then
			error "Düzen numarası belirtilmelidir"
			return 1
		fi

		if ! is_in_tmux; then
			error "Tmux oturumunda değilsiniz"
			return 1
		fi

		create_layout "$(tmux_cmd display-message -p '#S')" "$1"
		;;
		"")
			local session_name
			session_name="$(get_session_name)"
			create_session "$session_name"
			;;
	*)
		# Oturum adı olarak yorumla
		create_session "$command"
		;;
	esac
}

#--------------------------------------
# MAIN FUNCTION
#--------------------------------------

main() {
	local module="${1:-}"
	shift 2>/dev/null || true

	# Tmux sürüm kontrolü (sadece bir kere)
	check_tmux_version

	# Hiçbir parametre verilmezse KENP oturumu başlat
	if [[ -z "$module" ]]; then
		kenp_session_mode
		return $?
	fi

	case "$module" in
	"session" | "s")
		process_session_commands "$@"
		;;
	"buffer" | "b")
		process_buffer_commands "$@"
		;;
	"clip" | "c")
		process_clipboard_commands "$@"
		;;
	"plugin" | "p")
		process_plugin_commands "$@"
		;;
	"speed" | "cmd")
		process_speed_commands "$@"
		;;
	"config" | "cfg")
		process_config_commands "$@"
		;;
	"help" | "h" | "-h" | "--help")
		process_help_commands "$@"
		;;
	"kenp" | "k")
		kenp_session_mode "$@"
		;;
	"tmx")
		process_tmx_commands "$@"
		;;
	"version" | "-v" | "--version")
		echo "tm.sh v${VERSION}"
		;;
	*)
		# Varsayılan davranış - oturum adı olarak yorumla
		if validate_session_name "$module"; then
			create_session "$module"
		else
			error "Bilinmeyen komut veya geçersiz oturum adı: $module"
				info "Yardım için: $SCRIPT_NAME help"
				return 1
			fi
		;;
	esac
}

# Ana fonksiyonu tüm parametrelerle çalıştır
main "$@"
