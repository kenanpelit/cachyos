#!/usr/bin/env bash
# ==============================================================================
# Script: ente-run.sh
# Description: Launches Ente Auth with GNOME Keyring Secrets support.
# Usage: ente-run.sh
# ==============================================================================
# Authorship: Kenan Pelit
# Version: 1.0

set -euo pipefail

# ------------------------------------------------------------------------------
# ✨ Colors (Catppuccin Mocha)
# ------------------------------------------------------------------------------
BOLD="\e[1m"
RESET="\e[0m"
LBLUE="\e[38;2;137;180;250m"
LRED="\e[38;2;243;139;168m"
LGREEN="\e[38;2;166;227;161m"
LYELLOW="\e[38;2;249;226;175m"
LMAUVE="\e[38;2;203;166;247m"

# ------------------------------------------------------------------------------
# 🔔 Desktop toast (margo mshellctl, notify-send fallback, else silent)
# ------------------------------------------------------------------------------
toast() {
	local title="$1" body="${2:-}" sev="${3:-calm}"
	if command -v mshellctl >/dev/null 2>&1; then
		mshellctl toast "$title" "$body" --severity "$sev" >/dev/null 2>&1 || true
	elif command -v notify-send >/dev/null 2>&1; then
		notify-send -a "Ente Auth" "$title" "$body" >/dev/null 2>&1 || true
	fi
}

# ------------------------------------------------------------------------------
# 🧩 Header
# ------------------------------------------------------------------------------
printf "\n${LBLUE}${BOLD}==> Ente Auth Launcher${RESET}\n"

# ------------------------------------------------------------------------------
# 🔁 Already running? Surface it and exit (don't spawn a second instance).
# ------------------------------------------------------------------------------
if pgrep -x enteauth >/dev/null 2>&1 \
	|| pgrep -x ente_auth >/dev/null 2>&1 \
	|| pgrep -f 'io\.ente\.auth' >/dev/null 2>&1; then
	printf "${LGREEN}✓ Ente Auth is already running.${RESET}\n"
	toast "Ente Auth" "Zaten çalışıyor" calm
	exit 0
fi

printf "${LMAUVE}Checking D-Bus and Secret Service environment...${RESET}\n"

# ------------------------------------------------------------------------------
# 🧠 Ensure D-Bus session is defined
# ------------------------------------------------------------------------------
if [[ -z "${DBUS_SESSION_BUS_ADDRESS:-}" ]]; then
	export DBUS_SESSION_BUS_ADDRESS="unix:path=${XDG_RUNTIME_DIR}/bus"
	printf "${LYELLOW}→ D-Bus session address was missing, defined automatically.${RESET}\n"
else
	printf "${LGREEN}✓ D-Bus session detected.${RESET}\n"
fi

# ------------------------------------------------------------------------------
# 🔐 Ensure Secret Service (org.freedesktop.secrets) is running
# ------------------------------------------------------------------------------
if ! busctl --user list 2>/dev/null | grep -q org.freedesktop.secrets; then
	printf "${LYELLOW}→ Starting GNOME Keyring (secrets-only)...${RESET}\n"
	if gkd_bin="$(command -v gnome-keyring-daemon 2>/dev/null)"; then
		"$gkd_bin" --foreground --components=secrets >/dev/null 2>&1 &
		sleep 0.3
		printf "${LGREEN}✓ Secret Service started successfully.${RESET}\n"
	else
		printf "${LRED}✗ gnome-keyring-daemon not found!${RESET}\n"
		exit 1
	fi
else
	printf "${LGREEN}✓ Secret Service is already running.${RESET}\n"
fi

# ------------------------------------------------------------------------------
# 🚀 Launch Ente Auth
# ------------------------------------------------------------------------------
printf "${LMAUVE}Launching Ente Auth...${RESET}\n"

# Prefer native binaries first, then Flatpak app id.
toast "Ente Auth" "Başlatılıyor…" calm
if ente_bin="$(command -v enteauth 2>/dev/null)"; then
	exec "$ente_bin"
elif ente_bin="$(command -v ente-auth 2>/dev/null)"; then
	exec "$ente_bin"
elif ente_bin="$(command -v ente_auth 2>/dev/null)"; then
	exec "$ente_bin"
elif command -v flatpak >/dev/null 2>&1 && flatpak info --user io.ente.auth >/dev/null 2>&1; then
	exec flatpak run --user io.ente.auth
elif command -v flatpak >/dev/null 2>&1 && flatpak info io.ente.auth >/dev/null 2>&1; then
	exec flatpak run io.ente.auth
else
	printf "${LRED}✗ Ente Auth executable not found.${RESET}\n"
	printf "${LYELLOW}Hint:${RESET} install with ${BOLD}flatpak install flathub io.ente.auth${RESET}\n"
	toast "Ente Auth" "Çalıştırılabilir bulunamadı" danger
	exit 1
fi

# ------------------------------------------------------------------------------
# EOF
# ------------------------------------------------------------------------------
