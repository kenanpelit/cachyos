#!/usr/bin/env bash
# voca-doctor — vocalinux + whisper.cpp kurulumunun sağlık kontrolü.
#
# Kullanım:
#   voca-doctor                        tüm kontroller
#   voca-doctor --model                model profillerini listele (voca-model'e devreder)
#   voca-doctor --model small|turbo|large   profile geç (vocalinux yeniden başlar)
#   voca-doctor --bench small large-v3-turbo-q5_0
#                                      modelleri Vulkan ve CPU'da süreler; test cümlesi:
#                                      espeak-ng varsa Türkçe konuşma, yoksa 1 sn sessizlik.
#                                      (model adı: ggml-<ad>.bin)
#   voca-doctor --bench --clip F.wav MODEL...   kendi kaydınla (16 kHz mono wav) ölç
#   VOCA_BENCH_BACKENDS=vulkan voca-doctor --bench ...   yalnızca Vulkan (varsayılan: vulkan cpu)
#
# Kontroller: oturum/kısayol izinleri, pywhispercpp derlemesi (AVX2 + Vulkan),
# Vulkan cihazı, neural VAD (onnxruntime), seçili model, iGPU watchdog hataları,
# vocalinux'un boştaki CPU yükü. Çıkış kodu: ✗ varsa 1.
set -uo pipefail

SCRIPT_DIR="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"

fails=0
warns=0
ok()   { printf '%s✓%s %s\n' "$C_OK" "$C_RST" "$*"; }
warn() { printf '%s!%s %s\n' "$C_WARN" "$C_RST" "$*"; warns=$((warns + 1)); }
bad()  { printf '%s✗%s %s\n' "$C_BAD" "$C_RST" "$*"; fails=$((fails + 1)); }
hdr()  { printf '\n%s== %s ==%s\n' "$C_DIM" "$*" "$C_RST"; }

CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}/vocalinux/config.json"
MODELS="${XDG_DATA_HOME:-$HOME/.local/share}/vocalinux/models/whispercpp"

# ── --bench ────────────────────────────────────────────────────────────────
bench() {
  local clip="" model backend own_clip=false
  if [[ ${1:-} == --clip ]]; then clip="${2:?--clip bir wav dosyası ister}"; shift 2; fi
  if [[ -z $clip ]]; then
    clip="$(mktemp --suffix=.wav)"; own_clip=true
    if command -v espeak-ng >/dev/null; then
      # gerçek konuşma: decoder de çalışır (sessizlikte yalnızca encoder süresi ölçülür)
      espeak-ng -v tr -s 150 -w "$clip.raw.wav" "Bugün yedek almayı unuttum. Backup dosyalarını kontrol edip modeli değiştirmem gerekiyor." \
        && ffmpeg -v error -y -i "$clip.raw.wav" -ar 16000 -ac 1 "$clip"; rm -f "$clip.raw.wav"
      say "test kaydı: espeak-ng Türkçe cümle ($(ffprobe -v error -show_entries format=duration -of csv=p=0 "$clip" | cut -c1-4) sn)"
    else
      ffmpeg -v error -y -f lavfi -i anullsrc=r=16000:cl=mono -t 1 "$clip"
      say "test kaydı: 1 sn sessizlik (espeak-ng yok → yalnızca encoder süresi ölçülür)"
    fi
  fi
  say "model                    backend  3 ardışık çalıştırma (sn)   transkript"
  for model in "$@"; do
    [[ -f $MODELS/ggml-$model.bin ]] || { printf '%-24s (dosya yok: %s)\n' "$model" "$MODELS/ggml-$model.bin"; continue; }
    for backend in ${VOCA_BENCH_BACKENDS:-vulkan cpu}; do
      local env_prefix=()
      [[ $backend == cpu ]] && env_prefix=(env VK_ICD_FILENAMES=/nonexistent)
      "${env_prefix[@]}" python - "$MODELS/ggml-$model.bin" "$clip" "$model" "$backend" 2>/dev/null <<'PY'
import sys, time
from pywhispercpp.model import Model
path, clip, name, backend = sys.argv[1:5]
try:
    m = Model(path, n_threads=8, print_realtime=False, print_progress=False)
    ts, text = [], ""
    for _ in range(3):
        t = time.time(); segs = m.transcribe(clip, language="tr"); ts.append(round(time.time() - t, 1))
        text = " ".join(s.text.strip() for s in segs)
    print(f"{name:24s} {backend:7s}  {str(ts):26s}  {text[:90]}")
except Exception as e:
    print(f"{name:24s} {backend:7s}  HATA: {type(e).__name__}: {e}")
PY
    done
  done
  $own_clip && rm -f "$clip"
}

# --model: profil değiştir/listele (asıl iş voca-model.sh'ta)
if [[ "${1:-}" == "--model" ]]; then
  shift
  exec "$SCRIPT_DIR/voca-model.sh" "$@"
fi

if [[ "${1:-}" == "--bench" ]]; then
  shift
  [[ $# -gt 0 ]] || set -- small large-v3-turbo-q5_0
  bench "$@"
  exit 0
fi
if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  sed -n '2,18p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
  exit 0
fi

# ── 1. Oturum ve kısayol/yazma izinleri ────────────────────────────────────
hdr "Oturum"
sess="${XDG_SESSION_TYPE:-?}"
say "  oturum: $sess"
if [[ $sess == wayland ]]; then
  command -v wtype >/dev/null && ok "wtype var (Wayland metin yazma)" || bad "wtype yok — Wayland'de metin yazılamaz (pacman -S wtype)"
  command -v wl-copy >/dev/null && ok "wl-clipboard var" || warn "wl-clipboard yok (panoya kopyalama/yapıştırma yedeği)"
fi
if id -nG | tr ' ' '\n' | grep -qx input; then
  ok "kullanıcı 'input' grubunda (evdev kısayol dinleme)"
else
  bad "'input' grubunda değilsin — genel kısayol (push-to-talk) çalışmaz: sudo usermod -aG input \$USER"
fi

# ── 2. pywhispercpp derlemesi ──────────────────────────────────────────────
hdr "whisper.cpp (pywhispercpp)"
prov="$(voca_provider_pkg)"
if [[ -z $prov ]]; then
  bad "python-pywhispercpp-* kurulu değil → voca-build"
else
  [[ $prov == "$VOCA_PKG" ]] && ok "sağlayıcı: $prov" || warn "sağlayıcı: $prov (beklenen: $VOCA_PKG) → voca-build --force"
  sp="$(voca_site_packages)"
  avx=$(voca_count_insn "$sp/libggml-cpu.so" 'ymm')
  fma=$(voca_count_insn "$sp/libggml-cpu.so" 'vfmadd')
  if (( avx > 0 )); then
    ok "CPU çekirdekleri AVX2'li (ymm=$avx, FMA=$fma)"
  else
    bad "CPU çekirdekleri AVX2/FMA'SIZ (jenerik SSE2 derleme) — çok yavaş! → voca-build --force"
  fi
  [[ -f $sp/libggml-vulkan.so ]] && ok "Vulkan backend kütüphanesi var" || warn "libggml-vulkan.so yok (iGPU kullanılmaz) → voca-build --force"
  sysinfo="$(python -c 'import _pywhispercpp as p; print(p.whisper_print_system_info())' 2>/dev/null | tail -1)"
  [[ -n $sysinfo ]] && say "  ${C_DIM}${sysinfo}${C_RST}"
fi

if command -v vulkaninfo >/dev/null; then
  dev="$(vulkaninfo --summary 2>/dev/null | grep -m1 deviceName | sed 's/.*= *//')"
  [[ -n $dev ]] && ok "Vulkan cihazı: $dev" || warn "vulkaninfo cihaz bulamadı (vulkan-intel/vulkan-radeon kurulu mu?)"
else
  warn "vulkaninfo yok — vocalinux GPU seçemez (pacman -S vulkan-tools)"
fi

# ── 3. Neural VAD ──────────────────────────────────────────────────────────
hdr "Konuşma tespiti (VAD)"
if python -c 'import onnxruntime' 2>/dev/null; then
  ok "onnxruntime var (Silero neural VAD)"
else
  warn "onnxruntime yok → kaba genlik VAD'i; sessizlikte halüsinasyon (\"Altyazı M.K.\") artar (pacman -S python-onnxruntime)"
fi

# ── 4. Model ───────────────────────────────────────────────────────────────
hdr "Model"
if [[ -f $CONFIG ]]; then
  read -r engine lang model < <(python - "$CONFIG" <<'PY'
import json, sys
sr = json.load(open(sys.argv[1])).get("speech_recognition", {})
e = sr.get("engine", "?")
m = sr.get(f"{e}_model_variant") or sr.get(f"{e}_model_size", "?")
print(e, sr.get("language", "?"), m)
PY
)
  say "  motor=$engine  dil=$lang  model=$model"
  if [[ $engine == whisper_cpp ]]; then
    # vocalinux'ta "large" takma adı; upstream yalnızca sürümlü dosyayı yayınlar.
    if [[ $model == large ]]; then file="ggml-large-v3.bin"; else file="ggml-$model.bin"; fi
    [[ -f $MODELS/$file ]] && ok "model dosyası var: $file ($(du -h "$MODELS/$file" | cut -f1))" || bad "model dosyası yok: $MODELS/$file"
    case "$model" in
      large|large-v1|large-v2|large-v3)
        warn "'$model' (1.55 milyar parametre) iGPU/CPU'da 12-45 sn sürer ve xe watchdog'una takılabilir — large-v3-turbo-q5_0 veya small öner (README)";;
    esac
  fi
else
  warn "vocalinux config yok ($CONFIG) — henüz hiç çalıştırılmamış"
fi

# ── 5. Kernel GPU watchdog ─────────────────────────────────────────────────
hdr "GPU"
tmo="$(journalctl -k --since '-2h' --no-pager 2>/dev/null | grep -c 'Timedout job' || true)"
if (( ${tmo:-0} > 0 )); then
  warn "son 2 saatte $tmo adet xe 'Timedout job' (GPU watchdog) → vocalinux'ta 'ErrorDeviceLost'; daha küçük model kullan"
else
  ok "GPU watchdog hatası yok (son 2 saat)"
fi

# ── 6. Süreç ───────────────────────────────────────────────────────────────
hdr "vocalinux süreci"
pid="$(pgrep -f '/usr/bin/vocalinux$' | head -1 || true)"
if [[ -z $pid ]]; then
  say "  çalışmıyor (vocalinux ile başlat)"
else
  cpu="$(top -b -n2 -d1 -p "$pid" 2>/dev/null | tail -1 | awk '{print int($9)}')"
  if (( ${cpu:-0} > 50 )); then
    bad "pid $pid boşta %${cpu} CPU yiyor — takılmış transkripsiyon ya da SIMD'siz derleme (yeniden başlat)"
  else
    ok "pid $pid boşta (%${cpu:-0} CPU)"
  fi
fi

printf '\n'
if (( fails > 0 )); then
  say "${C_BAD}$fails sorun${C_RST}, $warns uyarı."
  exit 1
fi
say "${C_OK}sorun yok${C_RST} ($warns uyarı)."
