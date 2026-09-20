#!/usr/bin/env bash
# voca modülü ortak yardımcıları — build-pywhispercpp.sh ve voca-doctor.sh kaynak alır.
# Doğrudan çalıştırılmaz.

VOCA_PKG="python-pywhispercpp-vulkan"

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
