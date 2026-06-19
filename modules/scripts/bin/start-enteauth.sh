#!/usr/bin/env bash

APP_NAME="Ente Auth"
CMD="enteauth"

notify() {
	notify-send -a "$APP_NAME" "$1" "$2" 2>/dev/null || true
}

if ! command -v "$CMD" >/dev/null 2>&1; then
	notify "Başlatılamadı" "$CMD komutu bulunamadı."
	exit 1
fi

if pgrep -x "$CMD" >/dev/null 2>&1; then
	notify "Zaten çalışıyor" "$APP_NAME zaten aktif."
	exit 0
fi

notify "Başlatılıyor" "$APP_NAME başlatılıyor..."

nohup "$CMD" >/tmp/enteauth.log 2>&1 &

sleep 2

if pgrep -x "$CMD" >/dev/null 2>&1; then
	notify "Başlatıldı" "$APP_NAME başarıyla çalıştırıldı."
else
	notify "Hata" "$APP_NAME başlatılamadı. Log: /tmp/enteauth.log"
	exit 1
fi
