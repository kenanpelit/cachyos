#!/usr/bin/env bash
set -euo pipefail

# Login warmup without interactive prompts:
# - read secrets from pass store
# - unlock gpg agent (loopback)
# - unlock gnome keyring
# - send desktop notifications

delay="${NIRI_BOOT_PROMPT_DELAY:-6}"
gpg_pass_entry="${OSC_GPG_PASS_ENTRY:-kenp/gnupg}"
login_pass_entry="${OSC_LOGIN_PASS_ENTRY:-kenp/login}"
notify_enabled="${OSC_LOGIN_PROMPTS_NOTIFY:-1}"

notify() {
  local urgency="${1:-normal}" title="${2:-Niri Login}" body="${3:-}"
  [[ "${notify_enabled}" == "1" ]] || return 0
  command -v notify-send >/dev/null 2>&1 || return 0
  notify-send -u "${urgency}" -t 2500 "${title}" "${body}" >/dev/null 2>&1 || true
}

pass_first_line() {
  local entry="${1:-}"
  [[ -n "${entry}" ]] || return 1
  command -v pass >/dev/null 2>&1 || return 1
  PASSWORD_STORE_GPG_OPTS="--batch --yes --no-tty --pinentry-mode loopback" \
    pass show "${entry}" 2>/dev/null | head -n1
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
  sleep "${delay}"

  local gpg_passphrase=""
  local login_password=""
  local gpg_ok=1
  local keyring_ok=1

  gpg_passphrase="$(pass_first_line "${gpg_pass_entry}" || true)"
  login_password="$(pass_first_line "${login_pass_entry}" || true)"

  if [[ -n "${gpg_passphrase}" ]] && unlock_gpg_with_passphrase "${gpg_passphrase}"; then
    gpg_ok=0
    notify "low" "Niri Login" "GPG warmup tamamlandi."
  else
    notify "normal" "Niri Login" "GPG warmup atlandi/basarisiz (${gpg_pass_entry})."
  fi

  if [[ -n "${login_password}" ]] && unlock_keyring_with_password "${login_password}"; then
    keyring_ok=0
    notify "low" "Niri Login" "Keyring unlock tamamlandi."
  else
    notify "normal" "Niri Login" "Keyring unlock atlandi/basarisiz (${login_pass_entry})."
  fi

  if [[ ${gpg_ok} -eq 0 || ${keyring_ok} -eq 0 ]]; then
    notify "normal" "Niri Login" "Otomatik giris warmup tamamlandi."
  else
    notify "critical" "Niri Login" "Otomatik warmup basarisiz; pass girislerini kontrol et."
  fi
}

main "$@"
