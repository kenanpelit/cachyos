#!/usr/bin/env bash
# voca modülü ortak yardımcıları — build-pywhispercpp.sh ve voca-doctor.sh kaynak alır.
# Doğrudan çalıştırılmaz.

# mdots hook'ları `sudo -u` ile çalışır ve ortamı sıfırlar: XDG_RUNTIME_DIR kaybolunca
# `systemctl --user`, `journalctl --user` ve wpctl (PipeWire) kullanıcı oturumuna ulaşamaz.
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"

VOCA_PKG="python-pywhispercpp-vulkan"

# Boot'ta vocalinux'u başlatan systemd birimi (XDG autostart → systemd-xdg-autostart-generator).
VOCA_UNIT="app-vocalinux@autostart.service"

# Çalışan vocalinux sürecinin pid'i (yoksa boş).
# Komut satırından bağımsız olmalı: autostart `python /usr/bin/vocalinux --start-minimized`
# ile başlatır, elle çalıştırınca argümansızdır; sonu `$` ile sabitlenmiş bir `pgrep -f`
# deseni ilkini kaçırır (bu yüzden "çalışmıyor" sanılıp config'e dokunulmuştu).
# Önce süreç adı (comm=vocalinux), olmazsa komut satırının başından eşleş.
voca_pid() {
  local p
  p="$(pgrep -x vocalinux 2>/dev/null | head -1)"
  [[ -n $p ]] || p="$(pgrep -f '^/usr/bin/python[0-9.]* /usr/bin/vocalinux( |$)' 2>/dev/null | head -1)"
  printf '%s' "$p"
}

# vocalinux şu an systemd birimi olarak mı çalışıyor?
voca_unit_active() { systemctl --user is-active --quiet "$VOCA_UNIT" 2>/dev/null; }

# Symlink ile ~/.local/bin'e bağlansa bile modülün gerçek dizinini bul.
voca_module_dir() {
  local src="${BASH_SOURCE[1]:-${BASH_SOURCE[0]}}"
  dirname "$(dirname "$(readlink -f "$src")")"
}

voca_site_packages() {
  python -c 'import sysconfig; print(sysconfig.get_paths()["purelib"])'
}

# voca_count_insn <so-dosyası> <ERE> -> disassembly'de eşleşen satır sayısı (yoksa 0)
voca_count_insn() {
  local n
  n=$(objdump -d "$1" 2>/dev/null | grep -c -E "$2") || true
  echo "${n:-0}"
}

# Şu an kurulu pywhispercpp sağlayıcı paketi (yoksa boş)
voca_provider_pkg() {
  pacman -Qq 2>/dev/null | grep -E '^python-pywhispercpp' | head -1 || true
}

# 0 = kurulu kütüphane AVX2'li VE Vulkan'lı (sağlıklı), aksi halde 1
voca_pywhispercpp_healthy() {
  local sp cpu vk avx
  sp=$(voca_site_packages) || return 1
  cpu="$sp/libggml-cpu.so"
  vk="$sp/libggml-vulkan.so"
  [[ -f $cpu && -f $vk ]] || return 1
  avx=$(voca_count_insn "$cpu" 'ymm')
  (( avx > 0 ))
}

# Renkli çıktı (terminal değilse / NO_COLOR varsa düz metin)
if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
  C_OK=$'\033[32m' C_WARN=$'\033[33m' C_BAD=$'\033[31m' C_DIM=$'\033[2m' C_RST=$'\033[0m'
else
  C_OK='' C_WARN='' C_BAD='' C_DIM='' C_RST=''
fi
say()  { printf '%s\n' "$*"; }
info() { printf '  %s›%s %s\n' "$C_DIM" "$C_RST" "$*"; }
