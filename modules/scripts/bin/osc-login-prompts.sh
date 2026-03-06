#!/usr/bin/env bash
# ==============================================================================
# Script: osc-login-prompts
# Description: Session login warmup (GPG, Keyring, secrets) for non-interactive use.
# Usage: osc-login-prompts [options]
# ==============================================================================

set -euo pipefail

delay="${OSC_LOGIN_PROMPTS_DELAY:-${NIRI_BOOT_PROMPT_DELAY:-6}}"
gpg_pass_entry="${OSC_GPG_PASS_ENTRY:-kenp/gnupg}"
login_pass_entry="${OSC_LOGIN_PASS_ENTRY:-kenp/login}"
notify_enabled="${OSC_LOGIN_PROMPTS_NOTIFY:-1}"
bootstrap_dir="${OSC_LOGIN_PROMPTS_BOOTSTRAP_DIR:-$HOME/.config/osc-login-prompts}"
bootstrap_gpg_env="${OSC_GPG_BOOTSTRAP_PASSPHRASE:-}"
bootstrap_login_env="${OSC_LOGIN_BOOTSTRAP_PASSWORD:-}"
bootstrap_gpg_file="${OSC_GPG_BOOTSTRAP_FILE:-${bootstrap_dir}/gnupg.pass}"
bootstrap_login_file="${OSC_LOGIN_BOOTSTRAP_FILE:-${bootstrap_dir}/login.pass}"
log_enabled="${OSC_LOGIN_PROMPTS_LOG:-1}"
log_dir="${OSC_LOGIN_PROMPTS_LOG_DIR:-$HOME/.logs}"
log_file="${OSC_LOGIN_PROMPTS_LOG_FILE:-${log_dir}/osc-login-prompts.log}"
session_name="${OSC_LOGIN_PROMPTS_SESSION:-Niri Login}"
once_enabled=0

runtime_dir="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
once_stamp="${OSC_LOGIN_PROMPTS_STAMP:-${runtime_dir}/osc-login-prompts.done}"

usage() {
  cat <<EOF
Usage:
  osc-login-prompts [options]

Options:
  --delay <sec>     Delay before warmup (default: ${delay})
  --once            Skip if stamp already exists (${once_stamp})
  --stamp <path>    Custom stamp path (used with --once)
  --no-notify       Disable desktop notifications
  --notify          Enable desktop notifications
  --no-log          Disable log writing
  --log             Enable log writing
  --session <name>  Notification/log session name
  -h, --help        Show this help
EOF
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
    --delay)
      shift
      [[ $# -gt 0 ]] || { echo "Missing value for --delay" >&2; exit 2; }
      delay="$1"
      ;;
    --once)
      once_enabled=1
      ;;
    --stamp)
      shift
      [[ $# -gt 0 ]] || { echo "Missing value for --stamp" >&2; exit 2; }
      once_stamp="$1"
      ;;
    --no-notify)
      notify_enabled=0
      ;;
    --notify)
      notify_enabled=1
      ;;
    --no-log)
      log_enabled=0
      ;;
    --log)
      log_enabled=1
      ;;
    --session)
      shift
      [[ $# -gt 0 ]] || { echo "Missing value for --session" >&2; exit 2; }
      session_name="$1"
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
    esac
    shift
  done
}

log_line() {
  local level="${1:-INFO}" message="${2:-}"
  [[ "${log_enabled}" == "1" ]] || return 0
  mkdir -p "${log_dir}" >/dev/null 2>&1 || return 0
  printf '%s [%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "${level}" "${message}" >>"${log_file}" 2>/dev/null || true
}

notify() {
  local urgency="${1:-normal}" title="${2:-$session_name}" body="${3:-}"
  [[ "${notify_enabled}" == "1" ]] || return 0
  command -v notify-send >/dev/null 2>&1 || return 0
  notify-send -u "${urgency}" -t 2500 "${title}" "${body}" >/dev/null 2>&1 || true
}

warn_missing_bootstrap_file() {
  local label="${1:-Bootstrap}" path="${2:-}"
  [[ -n "${path}" ]] || return 0
  notify "normal" "Niri Login" "${label} dosyasi bulunamadi: ${path}"
  log_line "WARN" "${label} dosyasi bulunamadi: ${path}"
}

pass_first_line() {
  local entry="${1:-}"
  [[ -n "${entry}" ]] || return 1
  command -v pass >/dev/null 2>&1 || return 1
  PASSWORD_STORE_GPG_OPTS="--batch --yes --no-tty --pinentry-mode loopback" \
    pass show "${entry}" 2>/dev/null | head -n1
}

file_first_line() {
  local file_path="${1:-}"
  [[ -n "${file_path}" ]] || return 1
  [[ -r "${file_path}" ]] || return 1
  head -n1 "${file_path}" 2>/dev/null
}

unlock_gpg_with_passphrase() {
  local gpg_passphrase="${1:-}"
  [[ -n "${gpg_passphrase}" ]] || return 1
  command -v gpg >/dev/null 2>&1 || return 1

  local tmp_file="/tmp/.niri-gpg-test-$$.asc"
  if printf "niri-boot\n" \
    | gpg --batch --yes --no-tty --pinentry-mode loopback \
      --passphrase "${gpg_passphrase}" \
      --clearsign --output "${tmp_file}" >/dev/null 2>&1; then
    rm -f "${tmp_file}" 2>/dev/null || true
    return 0
  fi

  rm -f "${tmp_file}" 2>/dev/null || true
  return 1
}

unlock_keyring_with_password() {
  local login_password="${1:-}"
  [[ -n "${login_password}" ]] || return 1

  local gkd_bin=""
  if command -v gnome-keyring-daemon >/dev/null 2>&1; then
    gkd_bin="$(command -v gnome-keyring-daemon)"
  elif [[ -x /run/current-system/sw/libexec/gnome-keyring-daemon ]]; then
    gkd_bin="/run/current-system/sw/libexec/gnome-keyring-daemon"
  else
    return 1
  fi

  printf '%s' "${login_password}" | "${gkd_bin}" --unlock >/dev/null 2>&1
}

main() {
  parse_args "$@"

  if [[ "${once_enabled}" == "1" && -f "${once_stamp}" ]]; then
    log_line "INFO" "Warmup skip: stamp mevcut (${once_stamp})."
    exit 0
  fi

  sleep "${delay}"
  log_line "INFO" "Warmup basladi. gpg_entry=${gpg_pass_entry} login_entry=${login_pass_entry}"

  local gpg_passphrase=""
  local login_password=""
  local gpg_from_pass=""
  local login_from_pass=""
  local gpg_ok=1
  local keyring_ok=1
  local loop_detected=0

  gpg_from_pass="$(pass_first_line "${gpg_pass_entry}" || true)"
  login_from_pass="$(pass_first_line "${login_pass_entry}" || true)"
  gpg_passphrase="${gpg_from_pass}"
  login_password="${login_from_pass}"

  # pass -> gpg lock kisir dongu: bootstrap kaynagi ile kir.
  if [[ -z "${gpg_passphrase}" ]]; then
    if [[ -n "${bootstrap_gpg_env}" ]]; then
      gpg_passphrase="${bootstrap_gpg_env}"
      log_line "INFO" "GPG bootstrap env kullanildi."
    else
      if [[ -r "${bootstrap_gpg_file}" ]]; then
        gpg_passphrase="$(file_first_line "${bootstrap_gpg_file}" || true)"
        [[ -n "${gpg_passphrase}" ]] && log_line "INFO" "GPG bootstrap dosyasi kullanildi: ${bootstrap_gpg_file}"
      else
        warn_missing_bootstrap_file "GPG bootstrap" "${bootstrap_gpg_file}"
      fi
    fi
  fi

  if [[ -z "${gpg_from_pass}" && -z "${gpg_passphrase}" ]] && command -v pass >/dev/null 2>&1; then
    loop_detected=1
    notify "normal" "${session_name}" "Kisir dongu: pass kilitli, GPG sifresi pass'ten okunamadi."
    notify "normal" "${session_name}" "Cozum: OSC_GPG_BOOTSTRAP_PASSPHRASE veya ${bootstrap_gpg_file} kullan."
  fi

  if [[ -n "${gpg_passphrase}" ]] && unlock_gpg_with_passphrase "${gpg_passphrase}"; then
    gpg_ok=0
    notify "low" "${session_name}" "GPG warmup tamamlandi."
    log_line "INFO" "GPG warmup tamamlandi."
  else
    notify "normal" "${session_name}" "GPG warmup atlandi/basarisiz (${gpg_pass_entry})."
    log_line "WARN" "GPG warmup atlandi/basarisiz."
  fi

  # GPG acildiktan sonra pass tekrar okunabilir.
  if [[ -z "${login_password}" ]]; then
    login_password="$(pass_first_line "${login_pass_entry}" || true)"
  fi

  if [[ -z "${login_password}" ]]; then
    if [[ -n "${bootstrap_login_env}" ]]; then
      login_password="${bootstrap_login_env}"
      log_line "INFO" "Login bootstrap env kullanildi."
    else
      if [[ -r "${bootstrap_login_file}" ]]; then
        login_password="$(file_first_line "${bootstrap_login_file}" || true)"
        [[ -n "${login_password}" ]] && log_line "INFO" "Login bootstrap dosyasi kullanildi: ${bootstrap_login_file}"
      else
        warn_missing_bootstrap_file "Login bootstrap" "${bootstrap_login_file}"
      fi
    fi
  fi

  if [[ -n "${login_password}" ]] && unlock_keyring_with_password "${login_password}"; then
    keyring_ok=0
    notify "low" "${session_name}" "Keyring unlock tamamlandi."
    log_line "INFO" "Keyring unlock tamamlandi."
    if [[ "${once_enabled}" == "1" ]]; then
      mkdir -p "$(dirname "${once_stamp}")" >/dev/null 2>&1 || true
      : >"${once_stamp}" 2>/dev/null || true
    fi
  else
    notify "normal" "${session_name}" "Keyring unlock atlandi/basarisiz (${login_pass_entry})."
    log_line "WARN" "Keyring unlock atlandi/basarisiz."
  fi

  if [[ ${gpg_ok} -eq 0 && ${keyring_ok} -eq 0 ]]; then
    notify "normal" "${session_name}" "Otomatik giris warmup tamamlandi."
    log_line "INFO" "Warmup sonucu: tam basari."
  elif [[ ${gpg_ok} -eq 0 || ${keyring_ok} -eq 0 ]]; then
    notify "normal" "${session_name}" "Warmup kismen tamamlandi."
    log_line "INFO" "Warmup sonucu: kismi basari."
  elif [[ ${loop_detected} -eq 1 ]]; then
    notify "normal" "${session_name}" "Warmup skip: pass/gpg kisir dongu (bootstrap gerekli)."
    log_line "WARN" "Warmup sonucu: kisir dongu nedeniyle skip."
  else
    notify "critical" "${session_name}" "Otomatik warmup basarisiz; pass girislerini kontrol et."
    log_line "ERROR" "Warmup sonucu: basarisiz."
  fi
}

main "$@"
