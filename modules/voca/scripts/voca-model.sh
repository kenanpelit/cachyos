#!/usr/bin/env bash
# voca-model — vocalinux model profillerini listele / uygula / yedekle.
#
# Profiller modülün config/ dizininde tam config yedekleri olarak durur
# (config/vocalinux.<profil>.json). Uygulanırken canlı config'in SADECE model
# anahtarları değişir; kısayol, ses aygıtı vb. ayarların korunur.
#
# Kullanım:
#   voca-model                  mevcut model + profil listesi
#   voca-model small            profili uygula (vocalinux'u durdurup yeniden başlatır)
#   voca-model turbo
#   voca-model save [profil]    canlı config'i profil yedeğine yaz
#                               (profil verilmezse mevcut modele uyan profil)
#
# Profiller (bu makinede, Intel Arc iGPU, Vulkan — bkz. README ölçüm tablosu):
#   small  ggml-small.bin              ~1.3 sn   hızlı diktasyon, orta doğruluk
#   turbo  ggml-large-v3-turbo-q5_0    ~6.4 sn   yüksek doğruluk
#   large  ggml-large-v3.bin           12-45 sn  ORİJİNAL profil (vocalinux'un ilk hali); bu
#                                                donanımda önerilmez (iGPU watchdog'u — README)
set -euo pipefail

SCRIPT_DIR="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"
PROFILE_DIR="$(dirname "$SCRIPT_DIR")/config"
CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}/vocalinux/config.json"
RUN_LOG="${XDG_STATE_HOME:-$HOME/.local/state}/voca/vocalinux.log"
MODELS="${XDG_DATA_HOME:-$HOME/.local/share}/vocalinux/models/whispercpp"

profile_file() { printf '%s/vocalinux.%s.json' "$PROFILE_DIR" "$1"; }

# model kimliği (config'ten): varyant varsa o, yoksa boyut
model_of() {
  python - "$1" <<'PY'
import json, sys
sr = json.load(open(sys.argv[1]))["speech_recognition"]
print(sr.get("whisper_cpp_model_variant") or sr.get("whisper_cpp_model_size", "?"))
PY
}

model_file() { if [[ $1 == large ]]; then echo ggml-large-v3.bin; else echo "ggml-$1.bin"; fi; }

list_profiles() {
  local f name cur
  cur="$(model_of "$CONFIG" 2>/dev/null || echo '?')"
  say "mevcut model: ${C_OK}${cur}${C_RST}"
  say "profiller ($PROFILE_DIR):"
  for f in "$PROFILE_DIR"/vocalinux.*.json; do
    [[ -e $f ]] || continue
    name="$(basename "$f" .json)"; name="${name#vocalinux.}"
    local m; m="$(model_of "$f")"
    local mark=' '; [[ $m == "$cur" ]] && mark="${C_OK}*${C_RST}"
    local have="${C_OK}var${C_RST}"; [[ -f $MODELS/$(model_file "$m") ]] || have="${C_BAD}dosya yok${C_RST}"
    printf '  %s %-8s %-24s model dosyası: %s\n' "$mark" "$name" "$m" "$have"
  done
}

stop_vocalinux() {
  local pid i
  pid="$(pgrep -f '/usr/bin/vocalinux$' | head -1 || true)"
  [[ -n $pid ]] || return 1
  info "vocalinux durduruluyor (pid $pid)…"
  kill "$pid"
  for i in 1 2 3 4 5 6 7 8; do kill -0 "$pid" 2>/dev/null || return 0; sleep 1; done
  info "SIGTERM yetmedi → SIGKILL"
  kill -9 "$pid" 2>/dev/null || true
  sleep 1
  return 0
}

apply_profile() {
  local p="$1" pf m
  pf="$(profile_file "$p")"
  [[ -f $pf ]] || { say "${C_BAD}profil yok: $pf${C_RST}" >&2; list_profiles; exit 1; }
  [[ -f $CONFIG ]] || { say "${C_BAD}vocalinux config yok ($CONFIG) — önce bir kez çalıştır${C_RST}" >&2; exit 1; }
  m="$(model_of "$pf")"
  if [[ ! -f $MODELS/$(model_file "$m") ]]; then
    say "${C_BAD}model dosyası yok: $MODELS/$(model_file "$m")${C_RST}" >&2
    say "  vocalinux Settings → Model'den indir ya da: https://huggingface.co/ggerganov/whisper.cpp" >&2
    exit 1
  fi

  local was_running=false
  stop_vocalinux && was_running=true

  cp -f "$CONFIG" "$CONFIG.bak-voca-model"   # vocalinux çıkışta config'i yeniden yazar; durduktan SONRA düzenle
  python - "$CONFIG" "$pf" <<'PY'
import json, sys
live_path, prof_path = sys.argv[1:3]
live = json.load(open(live_path)); prof = json.load(open(prof_path))
for k in ("model_size", "whisper_cpp_model_size", "whisper_cpp_model_variant"):
    live["speech_recognition"][k] = prof["speech_recognition"][k]
json.dump(live, open(live_path, "w"), indent=4, ensure_ascii=False)
PY
  say "${C_OK}✓${C_RST} profil uygulandı: $p → $m   (önceki config: $CONFIG.bak-voca-model)"

  if $was_running; then
    mkdir -p "$(dirname "$RUN_LOG")"
    setsid -f vocalinux >"$RUN_LOG" 2>&1
    info "vocalinux yeniden başlatıldı; model yüklenirken birkaç sn sürer. Log: $RUN_LOG"
  else
    info "vocalinux çalışmıyordu; başlatmadım."
  fi
}

save_profile() {
  local p="${1:-}" cur
  [[ -f $CONFIG ]] || { say "${C_BAD}vocalinux config yok${C_RST}" >&2; exit 1; }
  cur="$(model_of "$CONFIG")"
  if [[ -z $p ]]; then
    case "$cur" in
      small) p=small ;;
      large-v3-turbo-q5_0) p=turbo ;;
      large) p=large ;;
      *) say "${C_BAD}mevcut model '$cur' bilinen bir profile uymuyor; profil adını ver: voca-model save <ad>${C_RST}" >&2; exit 1 ;;
    esac
  fi
  mkdir -p "$PROFILE_DIR"
  cp -f "$CONFIG" "$(profile_file "$p")"
  say "${C_OK}✓${C_RST} canlı config → $(profile_file "$p")   (model: $cur)"
}

case "${1:-list}" in
  list|"") list_profiles ;;
  save) save_profile "${2:-}" ;;
  -h|--help) sed -n '2,21p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//' ;;
  *) apply_profile "$1" ;;
esac
