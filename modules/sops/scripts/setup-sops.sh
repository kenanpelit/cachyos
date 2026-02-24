#!/usr/bin/env bash

# Sops age anahtarını güvenli bir şekilde yerleştirme betiği
set -euo pipefail

KEY_DIR="$HOME/.config/sops/age"
KEY_FILE="$KEY_DIR/keys.txt"
MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENCRYPTED_KEY="$MODULE_DIR/files/keys.txt.age"

if [ -f "$ENCRYPTED_KEY" ]; then
    if [ ! -f "$KEY_FILE" ]; then
        mkdir -p "$KEY_DIR"
        echo "=========================================================="
        echo "SOPS: Şifrelenmiş age anahtarı (keys.txt.age) bulundu."
        echo "Bu anahtarı çözmek için age parolanızı girin:"
        echo "=========================================================="
        
        if age -d -o "$KEY_FILE" "$ENCRYPTED_KEY"; then
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
