#!/usr/bin/env bash
# voca modülü — pre-install hook (paketlerden ÖNCE çalışır).
#
# Sıra önemli: packages.yaml'daki `vocalinux` (AUR) `python-pywhispercpp` ister.
# Bu bağımlılığı AUR yardımcısı, AVX2'siz/Vulkan'sız `python-pywhispercpp-cpu` ile
# karşılayabilir. Bu yüzden ÖNCE kendi derlediğimiz `python-pywhispercpp-vulkan`
# (provides=python-pywhispercpp) kurulur; vocalinux'un bağımlılığı onunla sağlanır.
#
# İdempotent: paket zaten AVX2+Vulkan'lıysa saniyeler içinde çıkar. Değilse derler
# (~4-8 dk, sudo gerekir). Elle: `voca-build [--force]`, doğrulama: `voca-doctor`.
set -euo pipefail

SCRIPT_DIR="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"

if ! command -v makepkg >/dev/null 2>&1; then
  say "voca: makepkg yok, atlanıyor" >&2
  exit 0
fi

# Hook root olarak tetiklendiyse asıl kullanıcıya dön (makepkg root'ta çalışmaz).
if [[ $EUID -eq 0 && -n "${SUDO_USER:-}" ]]; then
  exec sudo -u "$SUDO_USER" -H "$0" "$@"
fi

exec "$SCRIPT_DIR/build-pywhispercpp.sh"
