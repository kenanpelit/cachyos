#!/usr/bin/env bash
# ==============================================================================
# Script: osc-ports.sh
# Description: Network discovery, port scanning, and local listening-socket view.
# Usage: osc-ports.sh {discover|scan <host> <ports> [tcp|udp]|listen}
# ==============================================================================
# Features:
#   - LAN device discovery with MAC vendor lookup (nmap or ping sweep)
#   - TCP/UDP port scanning (nmap-accelerated, nc fallback)
#   - Single port / range (80-100) / list (80,443,8080) specs
#   - listen: show local listening sockets (ss)
#
#   License: MIT
#===============================================================================
set -uo pipefail

# Renk tanımlamaları
GREEN=$'\033[0;32m'
RED=$'\033[0;31m'
YELLOW=$'\033[1;33m'
NC=$'\033[0m'

# Hata yakalama
trap 'echo -e "\n${RED}Script sonlandırıldı!${NC}"; exit 1' SIGINT SIGTERM

have() { command -v "$1" >/dev/null 2>&1; }
is_root() { [ "${EUID:-$(id -u)}" -eq 0 ]; }

# Bir komutun gerektirdiği araçları kontrol et (komut bazlı)
require() {
	local missing=()
	local t
	for t in "$@"; do
		have "$t" || missing+=("$t")
	done
	if [ ${#missing[@]} -ne 0 ]; then
		echo -e "${RED}Eksik araçlar: ${missing[*]}${NC}" >&2
		echo -e "${YELLOW}Arch:${NC} sudo pacman -S nmap net-tools gnu-netcat iproute2 iputils" >&2
		exit 1
	fi
}

# Yardım fonksiyonu
show_help() {
	echo -e "${YELLOW}osc-ports — Ağ keşfi ve port tarama${NC}"
	echo -e "\n${YELLOW}KULLANIM:${NC} $0 <komut> [argümanlar]"
	echo -e "\n${YELLOW}Komutlar:${NC}"
	echo "  discover                         Ağdaki cihazları tara (MAC üretici ile)"
	echo "  scan <host> <port> [tcp|udp]     Uzak port tara"
	echo "  listen                           Yerel dinlenen portları göster"
	echo -e "\n${YELLOW}Port belirtimi:${NC}"
	echo "  tek: 80   |   aralık: 80-100   |   liste: 80,443,8080"
	echo -e "\n${YELLOW}Örnekler:${NC}"
	echo "  $0 discover"
	echo "  $0 scan 192.168.1.1 22,80,443"
	echo "  $0 scan scanme.nmap.org 1-1000 tcp"
	echo "  $0 listen"
	exit "${1:-1}"
}

# MAC adresi üretici bilgisi sorgulama
get_vendor_info() {
	local mac=$1
	local vendor="Bilinmiyor"
	local oui
	oui=$(echo "$mac" | tr -d ':-' | cut -c1-6 | tr '[:lower:]' '[:upper:]')

	if [ -f "/usr/share/nmap/nmap-mac-prefixes" ]; then
		vendor=$(grep -i "^$oui" "/usr/share/nmap/nmap-mac-prefixes" | cut -d' ' -f2- || echo "Bilinmiyor")
	elif [ -f "/var/lib/ieee-data/oui.txt" ]; then
		vendor=$(grep -i "^$oui" "/var/lib/ieee-data/oui.txt" | cut -d$'\t' -f3 || echo "Bilinmiyor")
	fi
	echo "${vendor:-Bilinmiyor}"
}

# Ağ keşif fonksiyonu
discover_network() {
	require ip
	local subnet
	subnet=$(ip -o -f inet addr show | awk '/scope global/ {print $4}' | head -n1)
	if [ -z "$subnet" ]; then
		echo -e "${RED}Ağ bilgisi alınamadı!${NC}"
		return 1
	fi

	echo -e "${YELLOW}Ağ taraması başlatılıyor: $subnet${NC}\n"
	arp -d &>/dev/null || true

	if have nmap; then
		echo -e "${YELLOW}Nmap ile ağ taraması yapılıyor...${NC}"
		nmap -sn "$subnet" | grep "Nmap scan report"
	else
		echo -e "${YELLOW}Ping taraması yapılıyor...${NC}"
		local prefix
		prefix=$(echo "$subnet" | cut -d'/' -f1 | rev | cut -d'.' -f2- | rev)
		for i in {1..254}; do
			(ping -c 1 -W 1 "$prefix.$i" >/dev/null 2>&1 && echo -e "${GREEN}Aktif host: $prefix.$i${NC}") &
		done
		wait
	fi

	if have arp; then
		echo -e "\n${YELLOW}ARP tablosu ve Cihaz Bilgileri:${NC}"
		printf "%-18s %-18s %s\n" "IP Adresi" "MAC Adresi" "Üretici"
		echo "=================================================================="
		while read -r line; do
			if [[ $line =~ \((.*)\).*at[[:space:]]([0-9a-fA-F:]+)[[:space:]] ]]; then
				local ip="${BASH_REMATCH[1]}" mac="${BASH_REMATCH[2]}" vendor
				vendor=$(get_vendor_info "$mac")
				printf "%-18s %-18s %s\n" "$ip" "$mac" "$vendor"
			fi
		done < <(arp -a | grep -v "incomplete")
	fi
}

# IP adresi kontrolü
validate_ip() {
	[[ $1 =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]
}

# Host erişilebilirlik kontrolü
check_host() {
	local host=$1
	echo -e "${YELLOW}Host kontrol ediliyor: $host${NC}"
	if ping -c 1 -W 1 "$host" >/dev/null 2>&1; then
		echo -e "${GREEN}Host aktif!${NC}"
		return 0
	fi
	echo -e "${RED}Host yanıt vermiyor (yine de taranıyor)...${NC}"
	return 1
}

# Tek port tarama (nc tabanlı, fallback)
nc_check_port() {
	local host=$1 port=$2 protocol=${3:-tcp}
	local timeout=1 nc_opts
	if ! [[ "$port" =~ ^[0-9]+$ ]] || [ "$port" -lt 1 ] || [ "$port" -gt 65535 ]; then
		echo -e "${RED}Geçersiz port numarası: $port${NC}"
		return 1
	fi
	[ "$protocol" = "tcp" ] && nc_opts="-z -w $timeout" || nc_opts="-zu -w $timeout"
	if nc $nc_opts "$host" "$port" 2>/dev/null; then
		echo -e "${GREEN}$port/$protocol açık${NC}"
	else
		echo -e "${RED}$port/$protocol kapalı${NC}"
	fi
}

# nc fallback: spec'i (tek/aralık/liste) tarar
nc_scan() {
	local host=$1 spec=$2 protocol=$3
	if [[ "$spec" == *-* ]]; then
		local start_port end_port
		IFS=- read -r start_port end_port <<<"$spec"
		if ! [[ "$start_port" =~ ^[0-9]+$ ]] || ! [[ "$end_port" =~ ^[0-9]+$ ]]; then
			echo -e "${RED}Geçersiz port aralığı${NC}"
			exit 1
		fi
		echo -e "${YELLOW}Port aralığı taranıyor ($protocol): $start_port - $end_port${NC}"
		local port
		for ((port = start_port; port <= end_port; port++)); do
			nc_check_port "$host" "$port" "$protocol"
		done
	elif [[ "$spec" == *,* ]]; then
		echo -e "${YELLOW}Port listesi taranıyor ($protocol)${NC}"
		local port
		IFS=',' read -ra PORTS <<<"$spec"
		for port in "${PORTS[@]}"; do
			nc_check_port "$host" "$port" "$protocol"
		done
	else
		nc_check_port "$host" "$spec" "$protocol"
	fi
}

# Port tarama: nmap varsa hızlı yol, yoksa nc fallback
do_scan() {
	local host=$1 spec=$2 protocol=${3:-tcp}

	# nmap TCP connect (-sT) root istemez; UDP (-sU) root ister.
	if have nmap && { [ "$protocol" = "tcp" ] || is_root; }; then
		local flag="-sT"
		[ "$protocol" = "udp" ] && flag="-sU"
		echo -e "${YELLOW}nmap ($protocol) ile taranıyor: $host [$spec]${NC}"
		nmap $flag -p "$spec" --open -Pn "$host" 2>/dev/null ||
			echo -e "${RED}nmap taraması başarısız${NC}"
	else
		require nc
		[ "$protocol" = "udp" ] && ! is_root &&
			echo -e "${YELLOW}(UDP taraması nmap+root olmadan güvenilmez)${NC}"
		nc_scan "$host" "$spec" "$protocol"
	fi
}

# Yerel dinlenen portlar
show_listen() {
	require ss
	echo -e "${YELLOW}Yerel dinlenen portlar (TCP/UDP):${NC}"
	is_root || echo -e "${YELLOW}(işlem adları için: sudo $0 listen)${NC}"
	ss -tulpn
}

# ==============================================================================
# Main
# ==============================================================================
[ $# -lt 1 ] && show_help

case "$1" in
discover)
	discover_network
	;;
scan)
	[ $# -lt 3 ] && show_help
	host=$2
	port_spec=$3
	protocol=${4:-tcp}

	if [ "$protocol" != "tcp" ] && [ "$protocol" != "udp" ]; then
		echo -e "${RED}Geçersiz protokol. 'tcp' veya 'udp' kullanın.${NC}"
		exit 1
	fi
	if ! validate_ip "$host" && ! host "$host" >/dev/null 2>&1; then
		echo -e "${RED}Geçersiz host adresi: $host${NC}"
		exit 1
	fi

	check_host "$host" || true

	START=$(date +%s)
	do_scan "$host" "$port_spec" "$protocol"
	END=$(date +%s)
	echo -e "\n${GREEN}Tarama tamamlandı!${NC} ${YELLOW}($((END - START)) sn)${NC}"
	;;
listen)
	show_listen
	;;
-h | --help | help)
	show_help 0
	;;
*)
	show_help
	;;
esac

exit 0
