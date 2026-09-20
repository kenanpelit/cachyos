#!/usr/bin/env bash
# voca-build — python-pywhispercpp-vulkan paketini derler ve kurar.
#
# AUR'daki python-pywhispercpp-{cpu,cuda,rocm} paketleri makepkg altında AVX2/FMA'sız
# (jenerik SSE2) derleniyor ve Vulkan içermiyor; vocalinux bu yüzden çok yavaş ya da
# kararsız çalışıyor. Bu script modüldeki PKGBUILD'i kullanır (nedenler PKGBUILD'in
# başındaki yorumda ve modules/voca/README.md'de).
#
# Kullanım:
#   voca-build              sağlıksızsa derle + kur (zaten AVX2+Vulkan'lıysa çıkar)
#   voca-build --force      sağlıklı olsa bile yeniden derle + kur
#   voca-build --no-install sadece derle (paket workdir'de kalır)
#   voca-build --workdir D  derleme dizini (varsayılan ~/.cache/voca-build)
set -euo pipefail

SCRIPT_DIR="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"
MODULE_DIR="$(dirname "$SCRIPT_DIR")"
PKGBUILD_DIR="$MODULE_DIR/pkgbuild/python-pywhispercpp-vulkan"

force=false
install=true
workdir="${XDG_CACHE_HOME:-$HOME/.cache}/voca-build"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --force) force=true ;;
    --no-install) install=false ;;
    --workdir) workdir="${2:?--workdir bir dizin ister}"; shift ;;
    -h|--help) sed -n '2,15p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) say "bilinmeyen argüman: $1 (bkz. --help)" >&2; exit 2 ;;
  esac
  shift
done

# Yapılacak iş yoksa (root dahil) her koşulda sessizce çık: mdots hook'u için önemli.
if ! $force && voca_pywhispercpp_healthy; then
  say "${C_OK}✓${C_RST} pywhispercpp zaten AVX2+Vulkan'lı ($(voca_provider_pkg)); yapılacak bir şey yok. (--force ile yeniden derle)"
  exit 0
fi

# makepkg root'la çalışmaz; sudo ile çağrıldıysa asıl kullanıcıya dön.
if [[ $EUID -eq 0 ]]; then
  if [[ -n "${SUDO_USER:-}" ]]; then
    exec sudo -u "$SUDO_USER" -H "$0" "$@"
  fi
  say "${C_BAD}root olarak çalıştırma; normal kullanıcıyla çalıştır (kurulumda sudo kendisi istenir).${C_RST}" >&2
  exit 1
fi

for tool in makepkg pacman objdump; do
  command -v "$tool" >/dev/null || { say "${C_BAD}gerekli araç yok: $tool${C_RST}" >&2; exit 1; }
done

say "${C_WARN}!${C_RST} Kurulu sağlayıcı: '$(voca_provider_pkg)' — AVX2/Vulkan yok ya da eksik. Derleniyor…"
say "  ${C_DIM}(ilk derleme whisper.cpp + Vulkan shader'ları yüzünden ~4-8 dk sürer)${C_RST}"

mkdir -p "$workdir"
cp -f "$PKGBUILD_DIR/PKGBUILD" "$workdir/PKGBUILD"
cd "$workdir"

# -s: eksik makedepends'i (cmake, ninja, shaderc, vulkan-headers…) sudo pacman ile kurar.
makepkg -sf --noconfirm 2>&1 | tee "$workdir/build.log"

pkg="$(ls -t "$workdir"/${VOCA_PKG}-*.pkg.tar.zst 2>/dev/null | grep -v -- '-debug-' | head -1 || true)"
[[ -f $pkg ]] || { say "${C_BAD}paket üretilemedi; bkz. $workdir/build.log${C_RST}" >&2; exit 1; }
info "üretilen paket: $pkg"

# Kurmadan önce içeriği doğrula: AVX2 (ymm) komutları + libggml-vulkan.so olmalı.
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
tar -C "$tmp" -xf "$pkg"
sp="$(find "$tmp" -type d -name site-packages | head -1)"
avx=$(voca_count_insn "$sp/libggml-cpu.so" 'ymm')
if (( avx == 0 )) || [[ ! -f $sp/libggml-vulkan.so ]]; then
  say "${C_BAD}✗ derlenen pakette AVX2 (ymm=$avx) veya libggml-vulkan.so eksik — kurulmadı.${C_RST}" >&2
  exit 1
fi
say "${C_OK}✓${C_RST} doğrulandı: AVX2 komutu=$avx, FMA=$(voca_count_insn "$sp/libggml-cpu.so" 'vfmadd'), Vulkan backend var."

if $install; then
  info "kuruluyor (mevcut python-pywhispercpp-* paketinin yerini alır)…"
  sudo pacman -U --noconfirm --ask 4 "$pkg"
  say "${C_OK}✓${C_RST} kuruldu. vocalinux'u YENİDEN BAŞLAT (çalışan süreç eski kütüphaneleri yüklü tutar)."
  say "  Kontrol: voca-doctor"
else
  say "${C_OK}✓${C_RST} --no-install: kurmak için: sudo pacman -U --ask 4 $pkg"
fi
