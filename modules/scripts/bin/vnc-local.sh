#!/usr/bin/env bash
# ==============================================================================
# Script: vnc-local.sh
# Description: Quick VNC connect to localhost:5901 using the pass-stored password.
# Usage: vnc-local
# ==============================================================================
# vnc-local - localhost:5901 VNC sunucusuna pass'taki parolayla hızlı bağlanır.
# Esnek/genel viewer için: osc-vnc.

# Pass'dan VNC parolasını al
VNC_PASS=$(pass vncpass 2>/dev/null)

# VNC parola dosyası yoksa oluştur
if [ ! -f ~/.vnc/passwd ]; then
	mkdir -p ~/.vnc/
	vncpasswd -f <<<"$VNC_PASS" >~/.vnc/passwd
	chmod 600 ~/.vnc/passwd
fi

# VNC bağlantısını kur (vncv wrapper: JDK 24+ native-access uyarısını bastırır,
# TurboVNC Helper JNI'sini yükler). vncv yoksa ham vncviewer'a düş.
viewer="vncviewer"
command -v vncv >/dev/null 2>&1 && viewer="vncv"
exec "$viewer" localhost:5901 -SecurityTypes VncAuth -passwd ~/.vnc/passwd
