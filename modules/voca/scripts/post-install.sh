#!/usr/bin/env bash
# voca modülü — post-install hook (paketlerden SONRA çalışır).
#
# Kurulumu doğrular: voca-doctor'ı çalıştırıp yalnızca sorun/uyarı satırlarını ve özeti
# gösterir. Bilgilendiricidir — sorun bulsa bile sync'i ASLA başarısız etmez (exit 0).
# Tam çıktı için: voca-doctor
set -uo pipefail

SCRIPT_DIR="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"

# vocalinux henüz kurulu değilse (ilk kurulumda paket adımı atlanmış olabilir) sessizce çık.
command -v vocalinux >/dev/null 2>&1 || { echo "voca: vocalinux kurulu değil, doğrulama atlandı"; exit 0; }

out="$(NO_COLOR=1 "$SCRIPT_DIR/voca-doctor.sh" 2>&1)" || true
problems="$(printf '%s\n' "$out" | grep -E '^(✗|!)' || true)"
summary="$(printf '%s\n' "$out" | grep -E 'sorun' | tail -1)"

if [[ -n $problems ]]; then
  printf '%s\n' "$problems"
fi
echo "voca: ${summary:-doctor çalıştırılamadı} (ayrıntı: voca-doctor)"
exit 0
