#!/usr/bin/env zsh
# ==============================================================================
# Script: vm-start.sh
# Description: Basit libvirt VM başlatıcı (win10 VM’ini başlatır)
# Usage: vm-start.sh
# ==============================================================================
# vm-start.sh - Basit libvirt VM başlatıcı
# win10 VM’ini başlatır, margo’da tag 6’ya geçip virsh ile çalıştırır.

# VM name
vm_name="win10"
export LIBVIRT_DEFAULT_URI="qemu:///system"

# switch to margo tag 6
mctl tags 6

virsh start ${vm_name}
virt-viewer -f -w -a ${vm_name}
