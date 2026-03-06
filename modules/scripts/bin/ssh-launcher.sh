#!/usr/bin/env bash
# ==============================================================================
# Script: ssh-launcher.sh
# Description: Launch SSH with optional menu selection using fzf/rofi
# Usage: ssh-launcher.sh [ssh_arguments]
# ==============================================================================
# ssh-launcher.sh - SSH bağlantı menüsü
# tanımlı hostları fzf/rofi ile seçip ssh başlatır; agent durumunu kontrol eder.
cd $HOME
exec ssh "$@"
