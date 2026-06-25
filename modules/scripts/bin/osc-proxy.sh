#!/usr/bin/env bash
# ==============================================================================
# Script: osc-proxy.sh
# Description: SSH SOCKS5 proxy manager. Her tünel bir SSH ControlMaster soketi
#              ile yönetilir; aynı anda farklı portlarda birden fazla tünel
#              çalışabilir. Durum/durdurma soket üzerinden yapılır (kırılgan
#              PID-grep yok).
#
# Usage: osc-proxy <komut> [argümanlar]
#   start <host> [port]      bir tünel başlat (varsayılan port 4999)
#   stop  [port|all]         tüneli (veya hepsini) durdur
#   restart <host> [port]    yeniden başlat
#   status [port]            bir tünelin (veya hepsinin) durumu
#   list                     aktif tünelleri listele
#   test  [port]             proxy üzerinden çıkış IP'sini test et
#   help                     bu yardım
#
# Ortam değişkenleri:
#   OSC_PROXY_PORT       varsayılan port (öntanımlı 4999)
#   OSC_PROXY_SSH_OPTS   ssh'a eklenecek ekstra seçenekler (boşlukla ayrılmış)
# ==============================================================================

set -euo pipefail

SCRIPT_NAME="SSH SOCKS Proxy"
DEFAULT_PORT="${OSC_PROXY_PORT:-4999}"
STATE_DIR="${XDG_RUNTIME_DIR:-/tmp}/osc-proxy"

# Renk kodları (terminal değilse devre dışı)
if [ -t 1 ]; then
	RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
	BLUE='\033[0;34m'; DIM='\033[2m'; NC='\033[0m'
else
	RED=''; GREEN=''; YELLOW=''; BLUE=''; DIM=''; NC=''
fi

msg()  { echo -e "$@"; }
err()  { echo -e "${RED}✗ $*${NC}" >&2; }
ok()   { echo -e "${GREEN}✓ $*${NC}"; }
warn() { echo -e "${YELLOW}! $*${NC}"; }

# ------------------------------------------------------------------------------
# Yardımcılar
# ------------------------------------------------------------------------------
ensure_state_dir() {
	mkdir -p "$STATE_DIR"
	chmod 700 "$STATE_DIR" 2>/dev/null || true
}

sock_path() { echo "$STATE_DIR/$1.sock"; }
host_path() { echo "$STATE_DIR/$1.host"; }
log_path()  { echo "$STATE_DIR/$1.log"; }

valid_port() {
	local p="$1"
	[[ "$p" =~ ^[0-9]+$ ]] && [ "$p" -ge 1 ] && [ "$p" -le 65535 ]
}

# Bu porttaki master canlı mı? (0 = canlı)
master_alive() {
	local port="$1" sock host
	sock="$(sock_path "$port")"
	host="$(saved_host "$port")"
	[ -S "$sock" ] || return 1
	[ -n "$host" ] || return 1
	ssh -O check -o ControlPath="$sock" "$host" >/dev/null 2>&1
}

saved_host() {
	local hf; hf="$(host_path "$1")"
	[ -f "$hf" ] && cat "$hf" || true
}

# Master PID'i (canlıysa) — `ssh -O check` "Master running (pid=NNNN)" basar
master_pid() {
	local port="$1" sock host
	sock="$(sock_path "$port")"; host="$(saved_host "$port")"
	[ -n "$host" ] || return 1
	ssh -O check -o ControlPath="$sock" "$host" 2>&1 \
		| grep -oE 'pid=[0-9]+' | grep -oE '[0-9]+' | head -1
}

# Ölü/artık soket dosyalarını temizle
cleanup_stale() {
	local port="$1"
	if ! master_alive "$port"; then
		rm -f "$(sock_path "$port")" "$(host_path "$port")"
	fi
}

list_ports() {
	ensure_state_dir
	local f port
	for f in "$STATE_DIR"/*.sock; do
		[ -e "$f" ] || continue
		port="$(basename "$f" .sock)"
		echo "$port"
	done
}

# ------------------------------------------------------------------------------
# Komutlar
# ------------------------------------------------------------------------------
start_proxy() {
	local host="${1:-}" port="${2:-$DEFAULT_PORT}"
	[ -n "$port" ] || port="$DEFAULT_PORT"

	if [ -z "$host" ]; then
		err "Hostname belirtilmedi"
		echo "Kullanım: $(basename "$0") start <host> [port]" >&2
		return 1
	fi
	if ! valid_port "$port"; then
		err "Geçersiz port: $port"
		return 1
	fi

	ensure_state_dir
	if master_alive "$port"; then
		warn "Port $port'da zaten bir tünel çalışıyor ($(saved_host "$port"), PID $(master_pid "$port"))"
		return 1
	fi
	cleanup_stale "$port"

	local sock log; sock="$(sock_path "$port")"; log="$(log_path "$port")"

	msg "${BLUE}SSH SOCKS proxy başlatılıyor...${NC}"
	msg "  Host: $host   Port: $port"

	# ControlMaster soketi tüneli yönetir. ExitOnForwardFailure: port doluysa
	# (ya da -D bağlanamazsa) ssh sessizce bağlanmak yerine hata ile çıkar.
	# -f auth+forward başarılı olunca arka plana geçer; çıkış kodu güvenilirdir.
	# shellcheck disable=SC2086
	if ssh -f -N -T \
		-D "$port" -C \
		-o ControlMaster=yes \
		-o ControlPath="$sock" \
		-o ExitOnForwardFailure=yes \
		-o ServerAliveInterval=60 \
		-o ServerAliveCountMax=3 \
		-o StrictHostKeyChecking=accept-new \
		-o LogLevel=ERROR \
		${OSC_PROXY_SSH_OPTS:-} \
		"$host" >"$log" 2>&1; then
		echo "$host" >"$(host_path "$port")"
		ok "Tünel açıldı (PID $(master_pid "$port"))"
		ok "SOCKS5 proxy: localhost:$port"
		msg "${DIM}  Tarayıcı: SOCKS5 host 127.0.0.1, port $port${NC}"
		msg "${DIM}  Test:     $(basename "$0") test $port${NC}"
	else
		err "Tünel başlatılamadı"
		[ -s "$log" ] && msg "${YELLOW}--- $log ---${NC}" && cat "$log" >&2
		rm -f "$sock"
		return 1
	fi
}

stop_one() {
	local port="$1" sock host
	sock="$(sock_path "$port")"; host="$(saved_host "$port")"
	if master_alive "$port"; then
		ssh -O exit -o ControlPath="$sock" "$host" >/dev/null 2>&1 || true
		ok "Port $port durduruldu ($host)"
	else
		warn "Port $port'da çalışan tünel yok"
	fi
	rm -f "$sock" "$(host_path "$port")" "$(log_path "$port")"
}

stop_proxy() {
	local target="${1:-$DEFAULT_PORT}"
	[ -n "$target" ] || target="$DEFAULT_PORT"

	if [ "$target" = "all" ]; then
		local any=0 port
		while IFS= read -r port; do
			[ -n "$port" ] || continue
			stop_one "$port"; any=1
		done < <(list_ports)
		[ "$any" -eq 0 ] && warn "Çalışan tünel yok"
		return 0
	fi

	if ! valid_port "$target"; then
		err "Geçersiz port: $target  (port numarası ya da 'all' bekleniyor)"
		return 1
	fi
	stop_one "$target"
}

restart_proxy() {
	local host="${1:-}" port="${2:-$DEFAULT_PORT}"
	[ -n "$port" ] || port="$DEFAULT_PORT"
	# host verilmediyse kayıtlı host'u kullan
	if [ -z "$host" ]; then
		host="$(saved_host "$port")"
		[ -n "$host" ] || { err "Host belirtilmedi ve port $port için kayıt yok"; return 1; }
	fi
	msg "${BLUE}Yeniden başlatılıyor (port $port)...${NC}"
	stop_proxy "$port" || true
	start_proxy "$host" "$port"
}

status_one() {
	local port="$1"
	if master_alive "$port"; then
		printf "${GREEN}● %-6s${NC} %-22s ${DIM}PID %s · socks5://127.0.0.1:%s${NC}\n" \
			"$port" "$(saved_host "$port")" "$(master_pid "$port")" "$port"
	else
		printf "${RED}○ %-6s${NC} %-22s ${DIM}(ölü soket, temizlendi)${NC}\n" \
			"$port" "$(saved_host "$port")"
		cleanup_stale "$port"
	fi
}

show_status() {
	local port="${1:-}"
	if [ -n "$port" ]; then
		valid_port "$port" || { err "Geçersiz port: $port"; return 1; }
		if [ -S "$(sock_path "$port")" ]; then
			status_one "$port"
		else
			msg "${RED}✗ Port $port'da tünel yok${NC}"
		fi
		return 0
	fi
	list_proxies
}

list_proxies() {
	local found=0 port
	while IFS= read -r port; do
		[ -n "$port" ] || continue
		[ "$found" -eq 0 ] && msg "${BLUE}Aktif tüneller:${NC}"
		status_one "$port"; found=1
	done < <(list_ports)
	[ "$found" -eq 0 ] && msg "${DIM}Çalışan tünel yok${NC}"
}

test_proxy() {
	local port="${1:-$DEFAULT_PORT}"
	[ -n "$port" ] || port="$DEFAULT_PORT"
	valid_port "$port" || { err "Geçersiz port: $port"; return 1; }

	if ! master_alive "$port"; then
		err "Port $port'da çalışan tünel yok"
		return 1
	fi
	if ! command -v curl >/dev/null 2>&1; then
		err "curl bulunamadı"
		return 1
	fi
	msg "${BLUE}Proxy üzerinden çıkış IP'si test ediliyor (port $port)...${NC}"
	local ip
	if ip="$(curl -fsS --max-time 15 --socks5-hostname "localhost:$port" https://ipinfo.io/ip 2>/dev/null)"; then
		ok "Çıkış IP: $ip"
	else
		err "Test başarısız (proxy yanıt vermedi)"
		return 1
	fi
}

show_help() {
	cat <<EOF
$(echo -e "${BLUE}$SCRIPT_NAME${NC}")

Kullanım:
  $(basename "$0") start <host> [port]    Tünel başlat (varsayılan port $DEFAULT_PORT)
  $(basename "$0") stop  [port|all]       Tüneli (veya hepsini) durdur
  $(basename "$0") restart <host> [port]  Yeniden başlat
  $(basename "$0") status [port]          Durum (port verilmezse hepsi)
  $(basename "$0") list                   Aktif tünelleri listele
  $(basename "$0") test  [port]           Proxy üzerinden çıkış IP'sini test et
  $(basename "$0") help                   Bu yardım

Örnekler:
  $(basename "$0") start tosun
  $(basename "$0") start hosman_nova154 5000
  $(basename "$0") list
  $(basename "$0") test 5000
  $(basename "$0") stop 5000
  $(basename "$0") stop all

Ortam değişkenleri:
  OSC_PROXY_PORT=$DEFAULT_PORT
  OSC_PROXY_SSH_OPTS   ssh'a eklenecek ekstra seçenekler
EOF
}

# ------------------------------------------------------------------------------
# Ana program
# ------------------------------------------------------------------------------
case "${1:-help}" in
	start)        shift; start_proxy "${1:-}" "${2:-}" ;;
	stop)         shift; stop_proxy "${1:-}" ;;
	restart)      shift; restart_proxy "${1:-}" "${2:-}" ;;
	status|st)    shift; show_status "${1:-}" ;;
	list|ls)      list_proxies ;;
	test)         shift; test_proxy "${1:-}" ;;
	help|-h|--help) show_help ;;
	*)            err "Bilinmeyen komut: ${1:-}"; echo; show_help; exit 1 ;;
esac
