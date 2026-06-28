#!/usr/bin/env bash
# ==============================================================================
# Script: svm.sh
# Description: Unified QEMU/KVM VM manager; per-distro config (svm <distro> ...).
# Usage: svm.sh <distro> [install|start|stop|status|connect|console|reset] [opts]
# ==============================================================================
# svm.sh — one engine, many distros.
#
#   The per-distro differences (ISO, disk dir, ports, memory, input devices,
#   extra host-forwards) live in small config files; this script is the shared
#   logic that every svm<distro> profile used to copy-paste.
#
#   Config files (sourced):  $SVM_CONF_DIR/<distro>.conf
#     default SVM_CONF_DIR =  /sun/san/shared/svm
#   Each conf sets CONFIG[...] keys; only the values that differ from the
#   defaults below are required (base_dir, vm_name, ssh_port, iso_url).
#
#   Commands:
#     install  Boot from ISO (first install)
#     start    Normal start (use --no-iso after install)
#     stop     Shutdown the VM (graceful, then force)
#     status   Show whether PID is alive
#     connect  SSH into the guest (user networking port-forward)
#     console  QEMU monitor console (unix socket)
#     reset    Remove disk/vars files (DANGEROUS)
#
#   Version: 2.0.0  (unified from svm{arch,cachy,ubuntu,nixos,nil})
#   Author: Kenan Pelit
# ==============================================================================

set -euo pipefail

# ============================================================================
# Environment Setup for Wayland/TTY
# ============================================================================
setup_wayland_environment() {
  export NO_AT_BRIDGE=1
  export GTK_A11Y=none
  export DBUS_SESSION_BUS_TIMEOUT=30000

  if [[ -n "${WAYLAND_DISPLAY:-}" ]]; then
    export QT_QPA_PLATFORM=wayland
    export GDK_BACKEND=wayland
    export SDL_VIDEODRIVER=wayland
    export CLUTTER_BACKEND=wayland
  fi

  if command -v fc-cache >/dev/null 2>&1; then
    fc-cache -f >/dev/null 2>&1 || true
  fi

  export GVFS_DISABLE_FUSE=1
  export XDG_SESSION_TYPE="${XDG_SESSION_TYPE:-wayland}"
}

setup_wayland_environment

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $*"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $*" >&2; }
log_error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $*"; }

# ============================================================================
# Distro / config resolution
# ============================================================================
SVM_CONF_DIR="${SVM_CONF_DIR:-/sun/san/shared/svm}"
DISTRO=""
SELF="svm"

list_distros() {
  local f found=0
  echo "Available distros (in $SVM_CONF_DIR):"
  for f in "$SVM_CONF_DIR"/*.conf; do
    [[ -e "$f" ]] || continue
    found=1
    printf '  %s\n' "$(basename "$f" .conf)"
  done
  [[ "$found" == 1 ]] || echo "  (none found — set SVM_CONF_DIR or add <distro>.conf)"
}

usage_top() {
  cat <<EOF
svm — unified QEMU/KVM VM manager (one engine, per-distro config)

Usage: svm <distro> [command] [options]

Commands: install | start | stop | status | connect | console | reset
Run 'svm <distro> --help' for the full option list.

EOF
  list_distros
}

init_config() {
  # Defaults shared by every distro. The per-distro .conf overrides what differs.
  declare -gA CONFIG=(
    [ovmf_code]="/usr/share/edk2-ovmf/x64/OVMF.4m.fd"
    [ovmf_vars_template]="/usr/share/edk2-ovmf/x64/OVMF_VARS.4m.fd"
    [memory]="16G"
    [cpus]="8"
    [disk_size]="128G"
    [vnc_port]="5900"
    [iso_checksum]=""
    [display_mode]="gtk"
    [gtk_gl]="on"
    [boot_mode]="bios"
    [boot_order]="auto"
    [shared_dir]="/run/user/$(id -u)"
    [attach_iso]="true"
    [daemonize]="false"
    [iso_file_explicit]="false"
    [input]="usb"          # usb|virtio (some guests, e.g. NixOS, prefer virtio)
    [extra_hostfwd]=""     # extra qemu user-net forwards, e.g. RDP
  )

  # Per-distro overrides.
  # shellcheck source=/dev/null
  source "$CONF_FILE"

  local k
  for k in base_dir vm_name ssh_port iso_url; do
    [[ -n "${CONFIG[$k]:-}" ]] || {
      log_error "config '$CONF_FILE' is missing required CONFIG[$k]"
      exit 1
    }
  done

  refresh_derived_paths
}

DRY_RUN=0
HAVE_KVM="false"
PARSED_COMMAND="start"

show_help() {
  cat <<EOF
svm — unified VM manager (distro: ${DISTRO})

Usage: $SELF [COMMAND] [OPTIONS]

Commands:
    install            Start the VM in installer mode (boot from ISO)
    start              Start the VM (default)
    stop               Stop the VM
    status             Show VM status
    connect            Connect via SSH
    console            Connect to QEMU monitor console
    reset              Reset VM configuration

Basic Options:
    -n, --name NAME        Set VM name (default: ${CONFIG[vm_name]})
    -m, --memory SIZE      Set memory size (default: ${CONFIG[memory]})
    -c, --cpus NUM         Set number of CPUs (default: ${CONFIG[cpus]})
    -p, --port PORT        Set SSH port (default: ${CONFIG[ssh_port]})
    -s, --size SIZE        Set disk size (default: ${CONFIG[disk_size]})
    --boot MODE            Set boot mode (bios or uefi) (default: ${CONFIG[boot_mode]})
    --boot-order ORDER     Boot order (auto|disk|cdrom) (default: ${CONFIG[boot_order]})

Display Options:
    -d, --daemon           Run in background
    --headless             Run without display
    --spice                Use SPICE display
    --vnc [PORT]           Use VNC display (default port: ${CONFIG[vnc_port]})
    --gtk-gl MODE          GTK OpenGL mode: on|off (default: ${CONFIG[gtk_gl]})

Path Options:
    --base-dir DIR         Set base directory (default: ${CONFIG[base_dir]})
    --iso-file PATH        Use custom ISO file
    --iso-url URL          Use custom ISO URL
    --checksum HASH        SHA256 checksum for ISO verification
    --shared-dir DIR       Shared directory path (default: ${CONFIG[shared_dir]})

Other Options:
    -h, --help             Show this help message
    --no-iso              Do not attach ISO (skip download/verify)
    --dry-run             Show QEMU command without executing
    -v, --verbose         Enable verbose output

Environment Variables (apply to any distro):
    SVM_CONF_DIR          Where <distro>.conf files live (default: /sun/san/shared/svm)
    VM_BASE_DIR           Override base directory
    VM_MEMORY             Override memory size
    VM_CPUS               Override CPU count
    VM_SSH_PORT           Override SSH port
    VM_BOOT_MODE          Override boot mode (bios/uefi)
    VM_GTK_GL             Override GTK OpenGL mode (on/off)

Examples:
    $SELF install                       # First install (boot from ISO)
    $SELF start                         # Start VM with defaults
    $SELF start --boot uefi --cpus 4    # UEFI mode, custom resources
    $SELF start --daemon --headless     # Background, no display
    $SELF connect                       # SSH into the guest
    $SELF status                        # Check VM status
    $SELF start --vnc 5901              # VNC display on custom port

Note: Use Ctrl+Alt+G to release mouse/keyboard grab in GUI mode.
EOF
}

apply_env_overrides() {
  [[ -n "${VM_BASE_DIR:-}" ]] && CONFIG[base_dir]="$VM_BASE_DIR"
  [[ -n "${VM_MEMORY:-}" ]] && CONFIG[memory]="$VM_MEMORY"
  [[ -n "${VM_CPUS:-}" ]] && CONFIG[cpus]="$VM_CPUS"
  [[ -n "${VM_SSH_PORT:-}" ]] && CONFIG[ssh_port]="$VM_SSH_PORT"
  [[ -n "${VM_BOOT_MODE:-}" ]] && CONFIG[boot_mode]="$VM_BOOT_MODE"
  [[ -n "${VM_GTK_GL:-}" ]] && CONFIG[gtk_gl]="$VM_GTK_GL"
  return 0
}

refresh_derived_paths() {
  local default_iso="${CONFIG[base_dir]}/$(basename "${CONFIG[iso_url]}")"
  if [[ "${CONFIG[iso_file_explicit]}" != "true" ]]; then
    CONFIG[iso_file]="$default_iso"
  fi

  CONFIG[vars_file]="${CONFIG[base_dir]}/OVMF_VARS.fd"
  CONFIG[disk_file]="${CONFIG[base_dir]}/disk.qcow2"
  CONFIG[monitor_sock]="${CONFIG[base_dir]}/monitor.sock"
  CONFIG[pid_file]="${CONFIG[base_dir]}/${CONFIG[vm_name]}.pid"
  CONFIG[log_file]="${CONFIG[base_dir]}/${CONFIG[vm_name]}.log"
}

prepare_environment() {
  refresh_derived_paths
  mkdir -p "${CONFIG[base_dir]}"
}

check_dependencies() {
  local deps=(qemu-system-x86_64 wget)
  local missing=()

  for dep in "${deps[@]}"; do
    if ! command -v "$dep" >/dev/null 2>&1; then
      missing+=("$dep")
    fi
  done

  if [[ ${#missing[@]} -gt 0 ]]; then
    log_error "Missing required dependencies: ${missing[*]}"
    log_info "Install them using your package manager:"
    log_info "  Arch: sudo pacman -S qemu-full wget"
    log_info "  Ubuntu: sudo apt install qemu-system-x86 wget"
    log_info "  NixOS: Add to your configuration.nix"
    exit 1
  fi

  if [[ ! -r /dev/kvm ]]; then
    HAVE_KVM="false"
    log_warn "KVM not available, VM will run without hardware acceleration"
    log_warn "Add your user to kvm group: sudo usermod -a -G kvm \$USER"
  else
    HAVE_KVM="true"
  fi
}

verify_iso() {
  local iso_file="$1"
  local checksum="${CONFIG[iso_checksum]}"

  if [[ -n "$checksum" && -f "$iso_file" ]]; then
    log_info "Verifying ISO checksum..."
    local actual_checksum
    actual_checksum=$(sha256sum "$iso_file" | cut -d' ' -f1)

    if [[ "$actual_checksum" != "$checksum" ]]; then
      log_error "ISO checksum mismatch!"
      log_error "Expected: $checksum"
      log_error "Actual:   $actual_checksum"
      return 1
    fi
    log_success "ISO checksum verified"
  fi
}

setup_vm_files() {
  if [[ ! -f "${CONFIG[disk_file]}" ]]; then
    log_info "Creating new disk image (${CONFIG[disk_size]})..."
    if [[ "${CONFIG[boot_mode]}" == "bios" ]]; then
      qemu-img create -f qcow2 -o compat=0.10 "${CONFIG[disk_file]}" "${CONFIG[disk_size]}"
    else
      qemu-img create -f qcow2 "${CONFIG[disk_file]}" "${CONFIG[disk_size]}"
    fi
    log_success "Disk image created"
  fi

  if [[ "${CONFIG[boot_mode]}" == "uefi" && ! -f "${CONFIG[vars_file]}" ]]; then
    if [[ ! -f "${CONFIG[ovmf_vars_template]}" ]]; then
      log_error "OVMF template not found: ${CONFIG[ovmf_vars_template]}"
      log_info "Install OVMF package (ovmf or edk2-ovmf)"
      exit 1
    fi
    log_info "Creating UEFI vars file..."
    cp "${CONFIG[ovmf_vars_template]}" "${CONFIG[vars_file]}"
    log_success "UEFI vars file created"
  fi

  if [[ "${CONFIG[attach_iso]}" == "true" ]]; then
    if [[ ! -f "${CONFIG[iso_file]}" ]]; then
      log_info "Downloading ISO from ${CONFIG[iso_url]}..."
      if ! wget --progress=bar:force:noscroll "${CONFIG[iso_url]}" -O "${CONFIG[iso_file]}"; then
        log_error "Failed to download ISO"
        rm -f "${CONFIG[iso_file]}"
        exit 1
      fi
      log_success "ISO downloaded"
    fi

    verify_iso "${CONFIG[iso_file]}"
  fi
}

build_qemu_command() {
  local -n out="$1"
  out=(qemu-system-x86_64)

  local accel="tcg"
  if [[ "$HAVE_KVM" == "true" ]]; then
    out+=(-enable-kvm)
    accel="kvm"
  fi

  out+=(-m "${CONFIG[memory]}")
  out+=(-smp "${CONFIG[cpus]}")
  out+=(-name "${CONFIG[vm_name]}")

  if [[ "${CONFIG[boot_mode]}" == "uefi" ]]; then
    out+=(-machine "type=q35,accel=${accel}")
  else
    out+=(-machine "type=pc,accel=${accel}")
  fi

  case "${CONFIG[boot_order]}" in
  disk) out+=(-boot order=c) ;;
  cdrom) out+=(-boot order=dc) ;;
  auto) : ;;
  *) log_error "Invalid boot order: ${CONFIG[boot_order]} (expected: auto|disk|cdrom)" && exit 1 ;;
  esac

  if [[ "${CONFIG[boot_mode]}" == "uefi" ]]; then
    out+=(-drive "file=${CONFIG[ovmf_code]},if=pflash,format=raw,readonly=on")
    out+=(-drive "file=${CONFIG[vars_file]},if=pflash,format=raw")
  fi

  out+=(-drive "file=${CONFIG[disk_file]},if=virtio,cache=writeback")
  if [[ "${CONFIG[attach_iso]}" == "true" ]]; then
    out+=(-cdrom "${CONFIG[iso_file]}")
  fi

  # Network with SSH (+ optional extra host-forwards, e.g. RDP for some guests)
  local netdev="user,id=net0,hostfwd=tcp::${CONFIG[ssh_port]}-:22"
  [[ -n "${CONFIG[extra_hostfwd]:-}" ]] && netdev+=",${CONFIG[extra_hostfwd]}"
  out+=(-netdev "$netdev")
  out+=(-device "virtio-net-pci,netdev=net0")

  case "${CONFIG[display_mode]}" in
  gtk)
    if [[ "${CONFIG[gtk_gl]}" == "on" ]]; then
      out+=(-device virtio-vga-gl)
      out+=(-display "gtk,gl=on")
    else
      log_warn "GTK GL is disabled; Wayland compositors may start without any outputs in the guest."
      out+=(-device virtio-vga)
      out+=(-display "gtk,gl=off")
    fi
    ;;
  spice)
    out+=(-device "qxl-vga,vgamem_mb=64")
    out+=(-spice "port=5930,addr=127.0.0.1,disable-ticketing=on")
    out+=(-device virtio-serial-pci)
    out+=(-chardev "spicevmc,id=vdagent,name=vdagent")
    out+=(-device "virtserialport,chardev=vdagent,name=com.redhat.spice.0")
    ;;
  vnc)
    out+=(-device virtio-vga)
    out+=(-vnc ":$((CONFIG[vnc_port] - 5900))")
    ;;
  none)
    out+=(-nographic)
    ;;
  *)
    log_error "Invalid display mode: ${CONFIG[display_mode]} (expected: gtk|spice|vnc|none)"
    exit 1
    ;;
  esac

  # Input devices (usb by default; virtio for guests that prefer it, e.g. NixOS)
  if [[ "${CONFIG[display_mode]}" != "none" ]]; then
    out+=(-device qemu-xhci,id=xhci)
    if [[ "${CONFIG[input]:-usb}" == "virtio" ]]; then
      out+=(-device virtio-tablet-pci)
      out+=(-device virtio-keyboard-pci)
    else
      out+=(-device usb-tablet)
      out+=(-device usb-kbd)
    fi
  fi

  if [[ "$HAVE_KVM" == "true" ]]; then
    out+=(-cpu host)
  else
    out+=(-cpu max)
  fi
  out+=(-device virtio-balloon-pci)
  out+=(-device virtio-rng-pci)

  if [[ -d "${CONFIG[shared_dir]}" ]]; then
    out+=(-fsdev "local,security_model=passthrough,id=fsdev0,path=${CONFIG[shared_dir]}")
    out+=(-device "virtio-9p-pci,id=fs0,fsdev=fsdev0,mount_tag=hostshare")
  fi

  if [[ "${CONFIG[display_mode]}" != "none" ]]; then
    out+=(-audiodev pa,id=snd0)
    out+=(-device intel-hda)
    out+=(-device hda-duplex,audiodev=snd0)
  fi

  out+=(-pidfile "${CONFIG[pid_file]}")

  if [[ "${CONFIG[daemonize]}" == "true" ]]; then
    out+=(-daemonize)
  fi

  out+=(-monitor "unix:${CONFIG[monitor_sock]},server,nowait")
}

vm_status() {
  if [[ -f "${CONFIG[pid_file]}" ]]; then
    local pid
    pid=$(cat "${CONFIG[pid_file]}")
    if kill -0 "$pid" 2>/dev/null; then
      log_success "VM is running (PID: $pid)"
      return 0
    else
      log_warn "PID file exists but process not running"
      rm -f "${CONFIG[pid_file]}"
    fi
  fi
  log_info "VM is not running"
  return 1
}

vm_stop() {
  if vm_status >/dev/null 2>&1; then
    local pid
    pid=$(cat "${CONFIG[pid_file]}")
    log_info "Stopping VM (PID: $pid)..."

    if [[ -S "${CONFIG[monitor_sock]}" ]]; then
      echo "system_powerdown" | socat - "unix:${CONFIG[monitor_sock]}" 2>/dev/null || true
    fi
    sleep 5

    if kill -0 "$pid" 2>/dev/null; then
      log_warn "Forcing VM shutdown..."
      kill -TERM "$pid"
      sleep 2
      kill -KILL "$pid" 2>/dev/null || true
    fi

    rm -f "${CONFIG[pid_file]}"
    rm -f "${CONFIG[monitor_sock]}" 2>/dev/null || true
    log_success "VM stopped"
  else
    log_info "VM is not running"
  fi
}

vm_connect() {
  if ! vm_status >/dev/null 2>&1; then
    log_error "VM is not running"
    exit 1
  fi

  log_info "Connecting to VM via SSH (port ${CONFIG[ssh_port]})..."

  if timeout 5 bash -c "cat < /dev/null > /dev/tcp/localhost/${CONFIG[ssh_port]}" 2>/dev/null; then
    ssh -p "${CONFIG[ssh_port]}" -o "UserKnownHostsFile=/dev/null" -o "StrictHostKeyChecking=no" localhost
  else
    log_error "SSH port ${CONFIG[ssh_port]} is not responding"
    log_info "VM might still be booting or SSH service is not running"
  fi
}

vm_console() {
  if ! vm_status >/dev/null 2>&1; then
    log_error "VM is not running"
    exit 1
  fi

  log_info "Connecting to QEMU monitor console..."
  socat - "unix:${CONFIG[monitor_sock]}"
}

vm_reset() {
  log_warn "This will remove all VM data for '${DISTRO}' (${CONFIG[base_dir]})!"
  read -p "Are you sure? (y/N): " -n 1 -r
  echo
  if [[ $REPLY =~ ^[Yy]$ ]]; then
    vm_stop
    rm -f "${CONFIG[disk_file]}" "${CONFIG[vars_file]}"
    log_success "VM reset completed"
  else
    log_info "Reset cancelled"
  fi
}

require_arg() {
  local opt="$1"
  local val="${2:-}"
  if [[ -z "$val" || "$val" == "-"* ]]; then
    log_error "Missing value for $opt"
    exit 1
  fi
}

parse_arguments() {
  local command="start"

  for arg in "$@"; do
    if [[ "$arg" == "-h" || "$arg" == "--help" ]]; then
      show_help
      exit 0
    fi
  done

  if [[ $# -gt 0 && ! "$1" =~ ^- ]]; then
    command="$1"
    shift
  fi

  while [[ $# -gt 0 ]]; do
    case $1 in
    -n | --name)
      require_arg "$1" "${2:-}"
      CONFIG[vm_name]="$2"
      shift 2
      ;;
    -m | --memory)
      require_arg "$1" "${2:-}"
      CONFIG[memory]="$2"
      shift 2
      ;;
    -c | --cpus)
      require_arg "$1" "${2:-}"
      CONFIG[cpus]="$2"
      shift 2
      ;;
    -p | --port)
      require_arg "$1" "${2:-}"
      CONFIG[ssh_port]="$2"
      shift 2
      ;;
    -s | --size)
      require_arg "$1" "${2:-}"
      CONFIG[disk_size]="$2"
      shift 2
      ;;
    --boot)
      require_arg "$1" "${2:-}"
      [[ "$2" != "bios" && "$2" != "uefi" ]] && {
        log_error "Boot mode must be 'bios' or 'uefi'"
        exit 1
      }
      CONFIG[boot_mode]="$2"
      shift 2
      ;;
    --boot-order)
      require_arg "$1" "${2:-}"
      CONFIG[boot_order]="$2"
      shift 2
      ;;
    -d | --daemon)
      CONFIG[daemonize]="true"
      [[ ${CONFIG[display_mode]} == "gtk" ]] && CONFIG[display_mode]="none"
      shift
      ;;
    --headless)
      CONFIG[display_mode]="none"
      shift
      ;;
    --spice)
      CONFIG[display_mode]="spice"
      shift
      ;;
    --gtk-gl)
      require_arg "$1" "${2:-}"
      if [[ "$2" != "on" && "$2" != "off" ]]; then
        log_error "--gtk-gl must be 'on' or 'off'"
        exit 1
      fi
      CONFIG[gtk_gl]="$2"
      shift 2
      ;;
    --vnc)
      CONFIG[display_mode]="vnc"
      [[ -n "${2:-}" && "$2" =~ ^[0-9]+$ ]] && {
        CONFIG[vnc_port]="$2"
        shift
      }
      shift
      ;;
    --base-dir)
      require_arg "$1" "${2:-}"
      CONFIG[base_dir]="$2"
      shift 2
      ;;
    --iso-file)
      require_arg "$1" "${2:-}"
      CONFIG[iso_file]="$2"
      CONFIG[iso_file_explicit]="true"
      shift 2
      ;;
    --iso-url)
      require_arg "$1" "${2:-}"
      CONFIG[iso_url]="$2"
      shift 2
      ;;
    --checksum)
      require_arg "$1" "${2:-}"
      CONFIG[iso_checksum]="$2"
      shift 2
      ;;
    --shared-dir)
      require_arg "$1" "${2:-}"
      CONFIG[shared_dir]="$2"
      shift 2
      ;;
    --no-iso)
      CONFIG[attach_iso]="false"
      shift
      ;;
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    -v | --verbose)
      set -x
      shift
      ;;
    *)
      log_error "Unknown option: $1"
      exit 1
      ;;
    esac
  done

  PARSED_COMMAND="$command"
}

print_cmd() {
  local -a cmd=("$@")
  printf '%q ' "${cmd[@]}"
  echo
}

main() {
  local command

  for arg in "$@"; do
    if [[ "$arg" == "-h" || "$arg" == "--help" ]]; then
      show_help
      exit 0
    fi
  done

  apply_env_overrides
  parse_arguments "$@"
  command="$PARSED_COMMAND"
  prepare_environment

  case "$command" in
  install)
    [[ "${CONFIG[attach_iso]}" == "false" ]] && CONFIG[attach_iso]="true"
    [[ "${CONFIG[boot_order]}" == "auto" ]] && CONFIG[boot_order]="cdrom"
    check_dependencies
    if vm_status >/dev/null 2>&1; then
      log_warn "VM is already running"
      exit 1
    fi
    setup_vm_files

    local -a qemu_cmd
    build_qemu_command qemu_cmd

    if ((DRY_RUN)); then
      log_info "QEMU command:"
      print_cmd "${qemu_cmd[@]}"
    else
      log_info "Starting VM (install mode)..."
      "${qemu_cmd[@]}"
    fi
    ;;
  start)
    check_dependencies
    if vm_status >/dev/null 2>&1; then
      log_warn "VM is already running"
      exit 1
    fi
    setup_vm_files

    local -a qemu_cmd
    build_qemu_command qemu_cmd

    if ((DRY_RUN)); then
      log_info "QEMU command:"
      print_cmd "${qemu_cmd[@]}"
    else
      log_info "Starting VM..."
      if [[ "${CONFIG[daemonize]}" == "true" ]]; then
        "${qemu_cmd[@]}" && log_success "VM started in background (PID file: ${CONFIG[pid_file]})"
      else
        "${qemu_cmd[@]}"
      fi
    fi
    ;;
  stop) vm_stop ;;
  status) vm_status ;;
  connect) vm_connect ;;
  console) vm_console ;;
  reset) vm_reset ;;
  *)
    log_error "Unknown command: $command"
    log_info "Use --help to see available commands"
    exit 1
    ;;
  esac
}

# ============================================================================
# Entry: resolve <distro>, load its config, then run.
# ============================================================================
case "${1:-}" in
"" | -h | --help | help)
  usage_top
  exit 0
  ;;
esac

DISTRO="$1"
shift
SELF="$(basename "$0") ${DISTRO}"
CONF_FILE="$SVM_CONF_DIR/$DISTRO.conf"

if [[ ! -f "$CONF_FILE" ]]; then
  log_error "unknown distro '$DISTRO' — no config at $CONF_FILE"
  list_distros
  exit 1
fi

init_config

trap 'log_info "Interrupted"; exit 130' INT TERM

main "$@"
