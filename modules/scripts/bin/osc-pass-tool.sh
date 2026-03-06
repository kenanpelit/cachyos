#!/usr/bin/env bash
# ==============================================================================
# Script: osc-pass-tool.sh
# Description: Import and export passwords for the pass password manager.
# Usage: osc-pass-tool.sh [import|export] [filename]
# ==============================================================================

set -euo pipefail

# Pass dizinini ayarla
export PASSWORD_STORE_DIR="$HOME/.pass"

# Fonksiyon: Kullanım bilgisi göster
show_usage() {
	echo "Kullanım: $0 [import|export] [dosya_adı]"
	echo "  import: Parolaları dosyadan pass veritabanına ekler"
	echo "  export: Pass veritabanındaki parolaları dosyaya çıkarır"
	echo ""
	echo "Örnek:"
	echo "  $0 import parolalar.txt"
	echo "  $0 export export_parolalar.txt"
	exit 1
}

# Fonksiyon: Import işlemi
do_import() {
	local input_file=$1
	local gpg_id=$(cat "$PASSWORD_STORE_DIR/.gpg-id")

	echo "🔐 Parola import işlemi başlıyor..."

	while IFS= read -r line; do
		[[ -z "$line" || "$line" =~ ^-+$ ]] && continue

		if [[ "$line" =~ ^[İi]sim:\ *(.*) ]]; then
			current_name="${BASH_REMATCH[1]}"
		elif [[ "$line" =~ ^Parola:\ *(.*) ]] && [[ -n "$current_name" ]]; then
			current_pass="${BASH_REMATCH[1]}"
			echo "$current_pass" | gpg --quiet --encrypt --recipient "$gpg_id" -o "$PASSWORD_STORE_DIR/$current_name.gpg"
			echo "✓ $current_name için parola eklendi"
			current_name=""
		fi
	done <"$input_file"

	echo "✨ Import işlemi tamamlandı"
}

# Fonksiyon: Export işlemi
do_export() {
	local output_file=$1

	echo "📤 Parola export işlemi başlıyor..."

	# Çıktı dosyasını oluştur/sıfırla
	>"$output_file"

	# Tüm parolaları al (secret_service ve test hariç)
	for password_file in $(find "$PASSWORD_STORE_DIR" -name '*.gpg' -not -path "*/secret_service/*"); do
		if [[ $password_file == *"/secret_service/"* ]] || [[ $password_file == *"test.gpg" ]]; then
			continue
		fi

		name=$(basename "$password_file" .gpg)
		password=$(pass show "$name")

		echo "İsim: $name" >>"$output_file"
		echo "Parola: $password" >>"$output_file"
		echo "------------------------" >>"$output_file"

		echo "✓ $name için parola export edildi"
	done

	echo "✨ Export işlemi tamamlandı"
}

# Ana program
case "${1:-}" in
import)
	[[ -z "${2:-}" ]] && show_usage
	do_import "$2"
	;;
export)
	[[ -z "${2:-}" ]] && show_usage
	do_export "$2"
	;;
*)
	show_usage
	;;
esac
