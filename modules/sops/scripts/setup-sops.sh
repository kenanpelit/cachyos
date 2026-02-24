#!/usr/bin/env bash

# Sops age anahtarını güvenli bir şekilde yerleştirme betiği
set -euo pipefail

# Eğer sudo ile çalışıyorsa asıl kullanıcının home dizinini bul
REAL_USER=${SUDO_USER:-$USER}
USER_HOME=$(getent passwd "$REAL_USER" | cut -d: -f6)

KEY_DIR="$USER_HOME/.config/sops/age"
KEY_FILE="$KEY_DIR/keys.txt"
MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENCRYPTED_KEY="$MODULE_DIR/files/keys.txt.age"

if [ -f "$ENCRYPTED_KEY" ]; then
    if [ ! -f "$KEY_FILE" ]; then
        mkdir -p "$KEY_DIR"
        # Klasör yetkilerini asıl kullanıcıya ver
        chown "$REAL_USER":"$REAL_USER" "$KEY_DIR" || true
        
        echo "=========================================================="
        echo "SOPS: Şifrelenmiş age anahtarı (keys.txt.age) bulundu."
        echo "Kullanıcı: $REAL_USER ($USER_HOME)"
        echo "Bu anahtarı çözmek için age parolanızı girin:"
        echo "=========================================================="
        
        # age komutunu asıl kullanıcı olarak çalıştır (tty/pinentry sorunlarını önlemek için)
        if sudo -u "$REAL_USER" age -d -o "$KEY_FILE" "$ENCRYPTED_KEY"; then
            chmod 600 "$KEY_FILE"
            echo "Anahtar başarıyla $KEY_FILE konumuna çıkarıldı."
        else
            echo "HATA: Parola yanlış veya işlem iptal edildi."
            exit 1
        fi
    else
        echo "SOPS: age anahtarı zaten mevcut ($KEY_FILE)."
    fi
else
    echo "UYARI: $ENCRYPTED_KEY dosyası bulunamadı."
    echo "Önce anahtarınızı oluşturun: age-keygen -o keys.txt"
    echo "Sonra parola ile şifreleyin: age -p -o modules/sops/files/keys.txt.age keys.txt"
fi
