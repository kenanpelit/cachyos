#!/usr/bin/env bash
# ==============================================================================
# Script: start-sayonara.sh
# Description: Sayonara müzik oynatıcıyı büyütülmüş arayüzle başlatır.
#              QT_SCALE_FACTOR=1.4 ile font + ikon + widget'lar 1.4x ölçeklenir.
#              Değeri değiştirmek istersen aşağıdaki SCALE'i düzenle.
# Usage: start-sayonara.sh [sayonara options] [files|dirs]
# ==============================================================================
SCALE="${SAYONARA_SCALE:-1.4}"
exec env QT_SCALE_FACTOR="$SCALE" sayonara "$@"
