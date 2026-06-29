#!/bin/bash
# deploy.sh - Deploy boot.img to Xiaomi Mi Note 3 (jason)
# Usage: ./scripts/deploy.sh [--build] [--flash] [--verify]
# Default: --build --flash --verify
#
# This script:
# 1. Builds boot.img from kernel + modified initramfs
# 2. Flashes to device via fastboot
# 3. Reboots and verifies SSH connectivity
#
# Prerequisites:
# - Device in fastboot mode (power off, hold Vol- + Power)
# - Kernel at /tmp/jason-emerg-build/kernel
# - Initramfs unpacked at /tmp/jason-initramfs/

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() { echo -e "${GREEN}[$(date +%H:%M:%S)]${NC} $*"; }
warn() { echo -e "${YELLOW}[$(date +%H:%M:%S)] WARN:${NC} $*"; }
err() { echo -e "${RED}[$(date +%H:%M:%S)] ERROR:${NC} $*" >&2; }

# Paths
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
KERNEL="/tmp/jason-emerg-build/kernel"
INITRAMFS_DIR="/tmp/jason-initramfs"
RAMDISK="/tmp/new-ramdisk.cpio.gz"
BOOT_IMG="/tmp/jason-boot-initramfs.img"
DEV_IP="172.16.42.1"
SSH_PASS="HOST_SUDO_PASS_PLACEHOLDER"

BUILD=true
FLASH=true
VERIFY=true

case "${1:-}" in
    --build-only) FLASH=false; VERIFY=false ;;
    --flash-only) BUILD=false; VERIFY=false ;;
    --verify-only) BUILD=false; FLASH=false ;;
    --help|-h)
        echo "Usage: $0 [--build-only|--flash-only|--verify-only]"
        echo "  Default: build + flash + verify"
        exit 0 ;;
esac

# === BUILD ===
if $BUILD; then
    log "=== BUILD PHASE ==="

    if [ ! -f "$KERNEL" ]; then
        err "Kernel not found at $KERNEL"
        err "Extract from existing boot.img: unpack_bootimg --boot_img /tmp/jason-old.img --out /tmp/jason-emerg-build"
        exit 1
    fi

    if [ ! -d "$INITRAMFS_DIR" ]; then
        err "Initramfs directory not found at $INITRAMFS_DIR"
        err "Unpack: mkdir -p $INITRAMFS_DIR && cd $INITRAMFS_DIR && gzip -dc /tmp/old-ramdisk.cpio.gz | cpio -idmv"
        exit 1
    fi

    log "Repacking initramfs..."
    cd "$INITRAMFS_DIR"
    find . | cpio -o -H newc 2>/dev/null | gzip > "$RAMDISK"
    log "Ramdisk size: $(du -h "$RAMDISK" | cut -f1)"

    log "Building boot.img..."
    python3 - "$KERNEL" "$RAMDISK" "$BOOT_IMG" << 'PYEOF'
import struct, sys

kernel_path, ramdisk_path, output_path = sys.argv[1], sys.argv[2], sys.argv[3]

with open(kernel_path, 'rb') as f:
    kernel = f.read()
with open(ramdisk_path, 'rb') as f:
    ramdisk = f.read()

PAGE_SIZE = 4096
BOOT_MAGIC = b'ANDROID!'

kernel_size = len(kernel)
ramdisk_size = len(ramdisk)

cmdline = (b'plymouth.ignore-serial-consoles plymouth.prefer-fbcon '
           b'loglevel=8 ignore_loglevel net.ifnames=0 earlycon '
           b'console=tty0 console=ttyMSM0,115200 fbcon=nodefer '
           b'pmos_boot_uuid=c3111c1f-5df3-4143-8005-7bc8abcb12c0 '
           b'pmos_root_uuid=55b176e9-7dba-4871-87cb-68314c590292 '
           b'pmos_rootfsopts=defaults')
cmdline = cmdline + b'\x00' * (512 - len(cmdline))

header = struct.pack('<8sIIIIIIIIII16s512s',
    BOOT_MAGIC, kernel_size, 0x00008000, ramdisk_size, 0x01000000,
    0, 0x00f00000, 0x00000100, PAGE_SIZE, 0, 0,
    b'\x00' * 16, cmdline)
header += b'\x00' * 32 + b'\x00' * 64
header = header + b'\x00' * (PAGE_SIZE - len(header))

def pad(data, ps=PAGE_SIZE):
    r = len(data) % ps
    return data + (b'\x00' * (ps - r) if r else b'')

with open(output_path, 'wb') as f:
    f.write(header + pad(kernel) + pad(ramdisk))

print(f"boot.img: {len(header) + len(pad(kernel)) + len(pad(ramdisk))} bytes")
PYEOF

    log "Boot image size: $(du -h "$BOOT_IMG" | cut -f1)"
    log "BUILD COMPLETE"
fi

# === FLASH ===
if $FLASH; then
    log "=== FLASH PHASE ==="

    log "Checking fastboot device..."
    if ! fastboot devices | grep -q fastboot; then
        err "No fastboot device found!"
        err "Enter fastboot mode: power off, hold Vol- + Power"
        err "Or from running device: echo 'bootonce-bootloader' | nc -w 2 $DEV_IP 2222"
        exit 1
    fi

    log "Flashing boot.img..."
    fastboot flash boot "$BOOT_IMG"

    log "Rebooting device..."
    fastboot reboot || true

    log "FLASH COMPLETE"
fi

# === VERIFY ===
if $VERIFY; then
    log "=== VERIFY PHASE ==="

    log "Waiting for device to come back..."
    sleep 10

    for i in $(seq 1 60); do
        if ping -c 1 -W 2 "$DEV_IP" >/dev/null 2>&1; then
            log "Device responding to ping (try $i)"
            break
        fi
        sleep 1
    done

    log "Waiting 20s for SSH to start..."
    sleep 20

    log "Testing SSH..."
    if sshpass -p "$SSH_PASS" ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
        -o ConnectTimeout=10 "user@$DEV_IP" \
        'echo "SSH OK"; uname -r; cat /proc/1/cmdline | tr "\0" " "; echo; uptime' 2>&1; then
        log "VERIFY COMPLETE - All checks passed!"
    else
        err "SSH verification failed!"
        err "Check: nc shell on port 2222, dmesg via nc listener"
        exit 1
    fi
fi

log "=== DEPLOYMENT SUCCESSFUL ==="
