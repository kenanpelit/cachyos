#!/usr/bin/env bash
# ==============================================================================
# Script: osc-safe-reboot.sh
# Description: Safe reboot/shutdown for Chrome/Brave/Chromium/Helium browsers without crash warnings
# Usage: osc-safe-reboot.sh [reboot|poweroff]
# ==============================================================================
set -euo pipefail

# TODO(margo): When invoked from a systemd --user service that isn't tied to a
# logind session, `systemctl reboot/poweroff` can fail with "Caller does not
# belong to any known session." The old Hyprland re-exec workaround was removed
# (margo-only cleanup); reboot_with_fallbacks() below now covers the session-less
# case via `-i`/`-f`/sudo. If a margo-native re-exec is ever needed, gate it here.

#--- Ayarlar -------------------------------------------------------------------
# NOTE: Google Chrome's command line is `/opt/google/chrome/chrome …` — it
# contains neither "brave" nor "chromium", so it needs its own pattern here or
# `pkill -f` never touches it (profile_chrome resolves google-chrome-stable).
GRACE_PATTERNS=("/opt/google/chrome/chrome" "brave" "chromium" "helium-browser" "helium-wrapper" "/opt/helium-browser-bin/helium")
SOFT_TIMEOUT=3   # SIGTERM sonrası bekleme (saniye)
HARD_DELAY=0.5   # KILL öncesi küçük bekleme
NOTIFY_TIME=3000 # Bildirim gösterim süresi (ms)

#--- Notify fonksiyonu ---------------------------------------------------------
send_notify() {
  local title="$1"
  local msg="$2"
  local urgency="${3:-normal}"

  if command -v notify-send &>/dev/null; then
    notify-send -u "$urgency" -t "$NOTIFY_TIME" "$title" "$msg"
  fi
}

reboot_with_fallbacks() {
  local errors=()

  if ! command -v systemctl &>/dev/null; then
    send_notify "OSC Safe Reboot" "systemctl bulunamadı" "critical"
    echo "[ERROR] systemctl not found"
    return 1
  fi

  echo "[STEP] Reboot deneniyor..."
  send_notify "OSC Safe Reboot" "Reboot deneniyor..." "critical"

  if systemctl reboot; then
    return 0
  else
    errors+=("systemctl reboot")
  fi

  if systemctl reboot -i; then
    return 0
  else
    errors+=("systemctl reboot -i")
  fi

  if systemctl reboot -f; then
    return 0
  else
    errors+=("systemctl reboot -f")
  fi

  if command -v sudo &>/dev/null; then
    if sudo -n systemctl reboot -f; then
      return 0
    else
      errors+=("sudo -n systemctl reboot -f")
    fi
  fi

  echo "[ERROR] Reboot başarısız oldu. Denenenler:"
  printf '  - %s\n' "${errors[@]}"
  echo "[INFO] Elle dene: sudo systemctl reboot -f"
  send_notify "OSC Safe Reboot" "Reboot başarısız. Elle dene: sudo systemctl reboot -f" "critical"
  return 1
}

#--- Brave/Chromium fix fonksiyonu ---------------------------------------------
json_edit_in_place() {
  local file="$1"
  local filter="$2"
  local tmp=""

  [[ -f "$file" ]] || return 0
  command -v jq >/dev/null 2>&1 || return 0

  tmp="$(mktemp "$(dirname "$file")/.${file##*/}.tmp.XXXXXX")"
  if jq "$filter" "$file" >"$tmp" 2>/dev/null; then
    mv -f "$tmp" "$file"
  else
    rm -f "$tmp" 2>/dev/null || true
    return 1
  fi
}

fix_profile_files_in_dir() {
  local base="$1"
  [[ -d "$base" ]] || return 0

  # Local State dosyası
  if [[ -f "$base/Local State" ]]; then
    json_edit_in_place "$base/Local State" '
      (.user_experience_metrics //= {}) |
      (.user_experience_metrics.stability //= {}) |
      .user_experience_metrics.stability.exited_cleanly = true |
      (.was //= {}) |
      .was.restarted = false
    ' || true
  fi

  # Profile*/Default Preferences
  local profiles=("$base"/Default "$base"/Profile* "$base"/System\ Profile "$base"/Guest\ Profile)
  for p in "${profiles[@]}"; do
    [[ -d "$p" ]] || continue
    if [[ -f "$p/Preferences" ]]; then
      json_edit_in_place "$p/Preferences" '
        (.profile //= {}) |
        .profile.exit_type = "Normal"
      ' || true
    fi
  done
}

fix_browser_flags() {
  # Brave - ana dizin
  fix_profile_files_in_dir "$HOME/.config/BraveSoftware/Brave-Browser"
  fix_profile_files_in_dir "$HOME/.config/BraveSoftware/Brave-Origin"
  fix_profile_files_in_dir "$HOME/.config/BraveSoftware/Brave-Origin-Beta"

  # Brave isolated (profile_brave --separate ile)
  # ~/.brave/isolated/<Class>/Local State + Profile*/Default
  if [[ -d "$HOME/.brave/isolated" ]]; then
    local d
    for d in "$HOME/.brave/isolated"/*; do
      [[ -d "$d" ]] || continue
      fix_profile_files_in_dir "$d"
    done
  fi

  # Chrome - ana dizin
  fix_profile_files_in_dir "$HOME/.config/google-chrome"

  # Chrome isolated (profile_chrome --separate ile)
  # ISOLATED_ROOT=~/.chrome, profiller doğrudan ~/.chrome/<Class> altında
  # (brave'in aksine ara "isolated" dizini yok): ~/.chrome/<Class>/Local State
  # + Default/Preferences.
  if [[ -d "$HOME/.chrome" ]]; then
    local d
    for d in "$HOME/.chrome"/*; do
      [[ -d "$d" ]] || continue
      fix_profile_files_in_dir "$d"
    done
  fi

  # Chromium (opsiyonel)
  if [[ -d "$HOME/.config/chromium" ]]; then
    fix_profile_files_in_dir "$HOME/.config/chromium"
  fi

  # Helium - ana dizin
  fix_profile_files_in_dir "$HOME/.config/net.imput.helium"

  # Helium isolated (profile_helium --separate ile)
  if [[ -d "$HOME/.helium/isolated" ]]; then
    local d
    for d in "$HOME/.helium/isolated"/*; do
      [[ -d "$d" ]] || continue
      fix_profile_files_in_dir "$d"
    done
  fi
}

#--- Uygulamaları graceful şekilde kapat ---------------------------------------
graceful_shutdown() {
  echo "[INFO] SIGTERM gönderiliyor: ${GRACE_PATTERNS[*]}"
  send_notify "🔄 Güvenli Reboot" "Tarayıcılar kapatılıyor..."

  for a in "${GRACE_PATTERNS[@]}"; do
    # -f kullan (komut satırında ara)
    if pgrep -f "$a" >/dev/null 2>&1; then
      echo "[INFO] $a bulundu, kapatılıyor..."
      pkill -TERM -f "$a" 2>/dev/null || true
    fi
  done

  echo "[INFO] ${SOFT_TIMEOUT}s bekleniyor..."
  sleep "$SOFT_TIMEOUT"

  # Hala açık olanları KILL
  local killed=0
  for a in "${GRACE_PATTERNS[@]}"; do
    if pgrep -f "$a" >/dev/null 2>&1; then
      echo "[WARN] $a hala açık, SIGKILL gönderiliyor..."
      pkill -KILL -f "$a" 2>/dev/null || true
      sleep "$HARD_DELAY"
      killed=1
    fi
  done

  if [[ $killed -eq 1 ]]; then
    send_notify "⚠️ Güvenli Reboot" "Bazı uygulamalar zorla kapatıldı" "critical"
  fi

  echo "[INFO] Tüm hedef uygulamalar kapatıldı."
}

#--- Ana akış ------------------------------------------------------------------
echo "[STEP] Uygulamalar kapatılıyor..."
graceful_shutdown

echo "[STEP] Brave/Chromium flag fix..."
fix_browser_flags
send_notify "OSC Safe Reboot" "Browser dosyaları güncellendi (clean exit)" "normal"

reboot_with_fallbacks
