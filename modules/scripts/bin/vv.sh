#!/usr/bin/env bash
# ==============================================================================
# Script: vv
# Description: Otomatik numaralandırma ile günlük not tutma aracı
# Usage: vv [SEÇENEK] [DOSYA]
# ==============================================================================
# Version: 1.5.0
# Date: 2026-06-21
# Author: Kenan Pelit
#
#   Features:
#   - Tarih bazlı otomatik dosya numaralandırma
#   - Alt dizin desteği (vv test/foo.txt gibi)
#   - fzf ile hızlı dosya seçimi (bat önizlemeli)
#   - fzf içinde Ctrl+D ile dosya silme, Ctrl+/ ile önizleme aç/kapa
#   - ripgrep ile tüm notlarda içerik araması (vv -g)
#   - Vim/nvim entegrasyonu, eşleşen satırda açma
#   - Gelişmiş hata kontrolü ve güvenlik (eval'siz editör çağrısı)
#   - Template desteği, TTY-farkında renkler (NO_COLOR)
#
#   License: MIT
#
# ==============================================================================

set -euo pipefail # Katı hata kontrolü

# Renk kodları — yalnızca terminale yazarken (NO_COLOR'a saygı duyar)
if [[ -t 2 && -z "${NO_COLOR:-}" ]]; then
	RED=$'\033[0;31m'
	GREEN=$'\033[0;32m'
	YELLOW=$'\033[1;33m'
	BLUE=$'\033[0;34m'
	NC=$'\033[0m'
else
	RED='' GREEN='' YELLOW='' BLUE='' NC=''
fi
readonly RED GREEN YELLOW BLUE NC

# Yapılandırma Değişkenleri (readonly ile sabitlendi)
readonly VV_DIR="${VV_DIR:-$HOME/.anote/scratch}"
readonly VV_EDITOR="${VV_EDITOR:-vim}"
readonly VV_EDITOR_OPTS="${VV_EDITOR_OPTS:--c \"set paste\"}"
readonly VV_DATE_FORMAT="${VV_DATE_FORMAT:-%Y%m%d}"
readonly VV_FILE_PERM="${VV_FILE_PERM:-644}" # 755 yerine 644 daha güvenli
readonly VV_DIR_PERM="${VV_DIR_PERM:-755}"
readonly VV_TEMPLATE="${VV_TEMPLATE:-}"
readonly VV_MAX_FILES="${VV_MAX_FILES:-100}" # fzf seçicide gösterilecek en yeni N dosya

#===============================================================================
# Yardımcı fonksiyonlar

# Renkli mesaj yazdırma
print_message() {
	local color="$1"
	local message="$2"
	printf '%b%s%b\n' "$color" "$message" "$NC" >&2
}

# Hata mesajı yazdırma ve çıkış
die() {
	print_message "$RED" "HATA: $1"
	exit 1
}

# Uyarı mesajı
warn() {
	print_message "$YELLOW" "UYARI: $1"
}

# Bilgi mesajı
info() {
	print_message "$BLUE" "$1"
}

# Başarı mesajı
success() {
	print_message "$GREEN" "$1"
}

# Güvenli dizin oluşturma
create_directory() {
	local dir="$1"
	local perm="$2"

	if [[ ! -d "$dir" ]]; then
		if ! mkdir -p "$dir"; then
			die "Dizin oluşturulamadı: $dir"
		fi
		chmod "$perm" "$dir"
		info "Dizin oluşturuldu: $dir"
	fi
}

# Güvenli dosya oluşturma
create_file() {
	local file="$1"
	local perm="$2"

	if [[ ! -f "$file" ]]; then
		# Template varsa içerikle, yoksa boş oluştur
		if [[ -n "$VV_TEMPLATE" && -f "$VV_TEMPLATE" ]]; then
			if ! cp "$VV_TEMPLATE" "$file"; then
				warn "Template kopyalanamadı; boş dosya oluşturuluyor"
				: >"$file"
			fi
		elif ! touch "$file"; then
			die "Dosya oluşturulamadı: $file"
		fi
		chmod "$perm" "$file"
	fi
}

# Dosya yolu validasyonu
validate_file_path() {
	local path="$1"

	# Güvenlik kontrolleri
	if [[ "$path" =~ \.\./|\.\.\\ ]]; then
		die "Güvenlik nedeniyle '..' içeren yollar kabul edilmez"
	fi

	if [[ "${path:0:1}" == "/" ]]; then
		die "Mutlak yollar kabul edilmez"
	fi

	# Dosya adı uzunluk kontrolü
	local filename
	filename=$(basename "$path")
	if [[ ${#filename} -gt 255 ]]; then
		die "Dosya adı çok uzun (maksimum 255 karakter)"
	fi
}

# Editör kontrolü
check_editor() {
	if ! command -v "$VV_EDITOR" >/dev/null 2>&1; then
		die "Editör bulunamadı: $VV_EDITOR"
	fi
}

# Editörü güvenli şekilde aç. İkinci argüman verilirse (satır no) ve editör
# vim/nvim ailesindense dosya o satırda açılır. VV_EDITOR_OPTS yalnızca
# kendi içinde ayrıştırılır; dosya yolu hiçbir zaman eval'lenmez.
open_in_editor() {
	local file_path="$1"
	local line="${2:-}"
	local -a opts=()

	if [[ -n "$VV_EDITOR_OPTS" ]]; then
		eval "opts=($VV_EDITOR_OPTS)"
	fi

	if [[ -n "$line" ]] && basename "$VV_EDITOR" | grep -qE '^(vim|nvim|gvim|vi|view)$'; then
		"$VV_EDITOR" "${opts[@]}" "+${line}" "$file_path"
	else
		"$VV_EDITOR" "${opts[@]}" "$file_path"
	fi
}

# Dosya listesi alma (en yeni N dosya — fzf performansı için)
get_file_list() {
	local max_files="$1"
	find "$VV_DIR" -type f -printf '%T@ %p\n' 2>/dev/null |
		sort -rn |
		head -n "$max_files" |
		cut -d' ' -f2-
}

# fzf önizleme komutları (bat varsa zengin, yoksa head)
if command -v bat >/dev/null 2>&1; then
	readonly PREVIEW_FILE='bat --style=numbers --color=always --line-range :300 -- {} 2>/dev/null'
	readonly PREVIEW_GREP='bat --style=numbers --color=always --highlight-line {2} -- {1} 2>/dev/null'
else
	readonly PREVIEW_FILE='head -n 300 -- {} 2>/dev/null'
	readonly PREVIEW_GREP='head -n 300 -- {1} 2>/dev/null'
fi

#===============================================================================
# Ana fonksiyonlar

# Yardım metni görüntüleme
show_help() {
	cat <<'EOF'
Kullanım: vv [SEÇENEK] [DOSYA]

Seçenekler:
  -h, --help          Bu yardım metnini göster
  -v, --version       Sürüm bilgisini göster
  -l, --list          Mevcut tüm dosyaları listele (sayı + boyut)
  -c, --clean         Boş dosyaları temizle
  -g, --grep [DESEN]  Tüm notlarda içerik ara (ripgrep + fzf, canlı)
  [DOSYA]             Belirtilen dosyayı aç (belirtilmezse otomatik numara verilir)
  [DİZİN/DOSYA]       Alt dizin ve dosya belirtilirse, o dizin altında dosya oluşturur

Açıklama:
  vv, günlük notlar oluşturmak ve düzenlemek için kullanılan bir araçtır.
  Otomatik numaralandırma ve tarih bazlı dosya organizasyonu sağlar.

Örnekler:
  vv                  Yeni dosya oluştur veya mevcut dosyalardan seç
  vv foo.txt          foo.txt dosyasını aç/oluştur
  vv test/foo.txt     test/foo.txt dosyasını aç/oluştur (dizin yoksa oluşturulur)
  vv -l               Tüm dosyaları listele
  vv -c               Boş dosyaları temizle
  vv -g               İçerik aramasını canlı başlat
  vv -g todo          "todo" geçen tüm notları ara, eşleşen satırda aç

Çevresel Değişkenler:
  VV_DIR              Not dizini (varsayılan: ~/.anote/scratch)
  VV_EDITOR           Editör (varsayılan: vim)
  VV_EDITOR_OPTS      Editör seçenekleri (varsayılan: -c "set paste")
  VV_DATE_FORMAT      Tarih formatı (varsayılan: %Y%m%d)
  VV_FILE_PERM        Dosya izinleri (varsayılan: 644)
  VV_TEMPLATE         Template dosyası yolu
  VV_MAX_FILES        Seçicide gösterilecek en yeni dosya sayısı (varsayılan: 100)
  NO_COLOR            Ayarlıysa renkli çıktı kapatılır

fzf Kısayolları:
  Enter               Seçili dosyayı düzenle
  Ctrl+D              Seçili dosyayı sil
  Ctrl+/              Önizlemeyi aç/kapa
  Ctrl+C/Esc          Çıkış

EOF
}

# Sürüm bilgisi
show_version() {
	echo "vv version 1.5.0"
}

# Dosya listesi gösterme
list_files() {
	local n size
	# || true: erişilemeyen alt dosya (Permission denied) du/find'i sıfır-dışı
	# döndürür; sayım/boyut kozmetik olduğundan bu set -e'yi tetiklememeli.
	n=$(find "$VV_DIR" -type f 2>/dev/null | wc -l || true)
	size=$(du -sh "$VV_DIR" 2>/dev/null | cut -f1 || true)
	info "Mevcut dosyalar (${n:-?} dosya, ${size:-?}):"
	if command -v tree >/dev/null 2>&1; then
		tree "$VV_DIR" -a -I '.git' || true
	else
		find "$VV_DIR" -type f 2>/dev/null | sort | sed "s|^$VV_DIR/||" || true
	fi
}

# Boş dosya temizleme
clean_empty_files() {
	local count=0
	while IFS= read -r -d '' file; do
		rm -- "$file"
		info "Silindi: $(basename "$file")"
		count=$((count + 1))
	done < <(find "$VV_DIR" -type f -empty -print0 2>/dev/null)

	success "Toplam $count boş dosya temizlendi"
}

# Sonraki dosya numarasını hesaplama
get_next_number() {
	local today="$1"
	local pattern="[0-9][0-9]_${today}.txt"

	local last_file
	last_file=$(find "$VV_DIR" -maxdepth 1 -type f -name "$pattern" 2>/dev/null | sort -V | tail -n 1)

	if [[ -n "$last_file" ]]; then
		local last_num
		last_num=$(basename "$last_file" | cut -d'_' -f1)
		printf "%02d" $((10#$last_num + 1))
	else
		echo "01"
	fi
}

# fzf ile gelişmiş dosya seçimi
select_file_with_fzf() {
	if ! command -v fzf >/dev/null 2>&1; then
		warn "fzf bulunamadı. Yeni dosya oluşturuluyor."
		return 1
	fi

	local file_list
	file_list=$(get_file_list "$VV_MAX_FILES")

	if [[ -z "$file_list" ]]; then
		info "Henüz dosya yok. Yeni dosya oluşturuluyor."
		return 1
	fi

	# Hem ilk yükleme hem de silme sonrası reload için ortak komut
	local reload_cmd
	reload_cmd="find \"$VV_DIR\" -type f -printf '%T@ %p\n' 2>/dev/null | sort -rn | head -n $VV_MAX_FILES | cut -d' ' -f2-"

	local selected_file
	selected_file=$(echo "$file_list" | fzf \
		--reverse \
		--preview "$PREVIEW_FILE" \
		--preview-window=right:60%:wrap \
		--prompt="Dosya (Ctrl+D=sil, Ctrl+/=önizleme, Enter=düzenle): " \
		--header="Toplam $(echo "$file_list" | wc -l) dosya gösteriliyor — içerik için: vv -g" \
		--bind "ctrl-/:toggle-preview" \
		--bind "ctrl-d:execute(printf 'Sil? %s [e/H] ' \"\$(basename {})\"; read -r c; [[ \$c =~ ^[Ee] ]] && rm -- {} || true)+reload($reload_cmd)") || true

	if [[ -n "$selected_file" && -f "$selected_file" ]]; then
		echo "$selected_file"
		return 0
	fi

	return 1
}

# ripgrep + fzf ile tüm notlarda içerik araması
grep_notes() {
	local query="${1:-}"

	if ! command -v fzf >/dev/null 2>&1; then
		die "İçerik araması için fzf gerekli"
	fi

	local rg_prefix
	if command -v rg >/dev/null 2>&1; then
		rg_prefix="rg --column --line-number --no-heading --color=always --smart-case"
	else
		warn "ripgrep yok; grep'e düşülüyor (daha yavaş, renksiz)"
		rg_prefix="grep -rIn --color=always"
	fi

	local selected
	selected=$(
		FZF_DEFAULT_COMMAND="$rg_prefix -- '' \"$VV_DIR\"" \
			fzf --ansi --disabled --query "$query" \
				--prompt 'İçerik ara> ' \
				--header 'Yaz: canlı ara · Enter: eşleşen satırda aç · Ctrl+/: önizleme' \
				--delimiter ':' \
				--bind "start:reload:$rg_prefix -- {q} \"$VV_DIR\" || true" \
				--bind "change:reload:sleep 0.1; $rg_prefix -- {q} \"$VV_DIR\" || true" \
				--bind "ctrl-/:toggle-preview" \
				--preview "$PREVIEW_GREP" \
				--preview-window 'right,60%,wrap,+{2}+3/3'
	) || true

	[[ -z "$selected" ]] && return 1

	# rg çıktısı: dosya:satır:sütun:metin
	local file line
	file="${selected%%:*}"
	line="${selected#*:}"
	line="${line%%:*}"

	if [[ -f "$file" ]]; then
		[[ "$line" =~ ^[0-9]+$ ]] || line=""
		open_in_editor "$file" "$line"
		return 0
	fi

	return 1
}

# Ana dosya işleme fonksiyonu
process_file() {
	local file_arg="$1"
	local file_path

	if [[ -z "$file_arg" ]]; then
		# Parametre yoksa fzf ile seçim yap
		if file_path=$(select_file_with_fzf); then
			open_in_editor "$file_path"
			return 0
		fi

		# Yeni dosya oluştur
		local today
		today=$(date +"$VV_DATE_FORMAT")
		local next_num
		next_num=$(get_next_number "$today")

		file_path="$VV_DIR/${next_num}_${today}.txt"
	else
		# Belirtilen dosyayı kullan
		validate_file_path "$file_arg"
		file_path="$VV_DIR/$file_arg"

		# Alt dizin oluştur
		local file_dir
		file_dir=$(dirname "$file_path")
		create_directory "$file_dir" "$VV_DIR_PERM"
	fi

	# Dosyayı oluştur ve aç
	create_file "$file_path" "$VV_FILE_PERM"
	open_in_editor "$file_path"
}

#===============================================================================
# Ana program

main() {
	# Parametre kontrolü
	case "${1:-}" in
	-h | --help)
		show_help
		exit 0
		;;
	-v | --version)
		show_version
		exit 0
		;;
	-l | --list)
		list_files
		exit 0
		;;
	-c | --clean)
		clean_empty_files
		exit 0
		;;
	-g | --grep)
		create_directory "$VV_DIR" "$VV_DIR_PERM"
		check_editor
		grep_notes "${2:-}" || true # iptal/eşleşme yok hata değildir
		exit 0
		;;
	-*)
		die "Geçersiz seçenek: $1. Yardım için: vv --help"
		;;
	esac

	# Editör kontrolü
	check_editor

	# Ana dizin oluştur
	create_directory "$VV_DIR" "$VV_DIR_PERM"

	# Dosya işleme
	process_file "${1:-}"
}

# Ana fonksiyonu çalıştır
main "$@"
