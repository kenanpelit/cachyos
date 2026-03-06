#!/usr/bin/env bash
# ==============================================================================
# Script: gnome-monitor-set.sh
# Description: Automatically sets external monitor as primary in GNOME.
# Usage: gnome-monitor-set.sh
# ==============================================================================

# Tüm monitör bilgisini al
monitor_list=$(gnome-monitor-config list)

# Harici ve dahili monitör isimlerini bul
external_monitor=$(echo "$monitor_list" | grep "^Monitor \[" | grep -v "eDP\|LVDS" | head -n1 | sed 's/Monitor \[ \(.*\) \] ON/\1/')
internal_monitor=$(echo "$monitor_list" | grep "^Monitor \[" | grep -E "eDP|LVDS" | head -n1 | sed 's/Monitor \[ \(.*\) \] ON/\1/')

if [ -z "$external_monitor" ]; then
	echo "❌ Harici monitör bulunamadı!"
	exit 1
fi

echo "🖥️  Harici monitör: $external_monitor"
echo "💻 Dahili monitör: $internal_monitor"
echo ""

# Logical monitor bölümünü al (son kısım)
logical_section=$(echo "$monitor_list" | sed -n '/^Logical monitor/,$p')

# Her monitör için bilgileri parse et
ext_line=$(echo "$logical_section" | grep -B1 "^\s*$external_monitor" | head -n1)
int_line=$(echo "$logical_section" | grep -B1 "^\s*$internal_monitor" | head -n1)

# Harici monitör değerleri
ext_coords=$(echo "$ext_line" | grep -oP '\[\s*\K[0-9x+]+')
ext_scale=$(echo "$ext_line" | grep -oP 'scale\s*=\s*\K[0-9.]+')
ext_res=$(echo "$ext_coords" | cut -d'+' -f1)
ext_x=$(echo "$ext_coords" | cut -d'+' -f2)
ext_y=$(echo "$ext_coords" | cut -d'+' -f3)

# Dahili monitör değerleri
int_coords=$(echo "$int_line" | grep -oP '\[\s*\K[0-9x+]+')
int_scale=$(echo "$int_line" | grep -oP 'scale\s*=\s*\K[0-9.]+')
int_res=$(echo "$int_coords" | cut -d'+' -f1)
int_x=$(echo "$int_coords" | cut -d'+' -f2)
int_y=$(echo "$int_coords" | cut -d'+' -f3)

# Mode ID'leri al - sed kullanarak daha güvenilir
ext_mode=$(echo "$monitor_list" | sed -n "/^Monitor \[ $external_monitor \]/,/^Monitor \[/p" | grep "CURRENT" | head -n1 | sed -n "s/.*\[id: '\([^']*\)'\].*/\1/p")
int_mode=$(echo "$monitor_list" | sed -n "/^Monitor \[ $internal_monitor \]/,/^Monitor \[/p" | grep "CURRENT" | head -n1 | sed -n "s/.*\[id: '\([^']*\)'\].*/\1/p")

echo "📊 Tespit edilen ayarlar:"
echo "   Harici: $ext_res @ scale $ext_scale, pozisyon ($ext_x,$ext_y)"
echo "          Mode ID: $ext_mode"
echo "   Dahili: $int_res @ scale $int_scale, pozisyon ($int_x,$int_y)"
echo "          Mode ID: $int_mode"
echo ""

# Değerleri kontrol et
if [ -z "$ext_mode" ] || [ -z "$int_mode" ]; then
	echo "❌ Mode ID'ler alınamadı!"
	exit 1
fi

echo "⚙️  Harici monitör birincil yapılıyor..."

gnome-monitor-config set \
	-LM "$external_monitor" -m "$ext_mode" -s "$ext_scale" -t normal -x "$ext_x" -y "$ext_y" -p \
	-LM "$internal_monitor" -m "$int_mode" -s "$int_scale" -t normal -x "$int_x" -y "$int_y"

if [ $? -eq 0 ]; then
	echo "✅ Başarılı! $external_monitor artık birincil monitör."
	echo "🔔 Bildirimler artık harici monitörde görünecek."
	echo ""

	# Test bildirimi gönder
	sleep 1
	notify-send -u normal "🖥️ Monitör Değiştirildi" "$external_monitor artık birincil ekran.\nBu bildirim harici monitörde görünüyor olmalı!" -t 5000
else
	echo "❌ Ayarlama başarısız oldu."
	exit 1
fi
