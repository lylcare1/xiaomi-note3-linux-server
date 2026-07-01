#!/bin/bash
# deploy.sh - Deploy r31 kernel + rootfs to Xiaomi Mi Note 3 (jason)
#
# Usage:
#   ./scripts/deploy.sh --update-uuid     # Update boot.img cmdline UUIDs from rootfs image
#   ./scripts/deploy.sh --flash-rootfs    # Flash rootfs to userdata via fastboot
#   ./scripts/deploy.sh --boot-temp       # Temporary boot via fastboot boot (no persistence)
#   ./scripts/deploy.sh --flash-boot      # Persist boot.img to boot partition via dd (from device)
#   ./scripts/deploy.sh --verify          # Verify SSH connectivity
#   ./scripts/deploy.sh --all             # Full deploy: update-uuid + flash-rootfs + boot-temp + verify
#   ./scripts/deploy.sh --persist         # Persist: flash-boot + verify (requires device running)
#
# Prerequisites:
#   - pmbootstrap export done (boot.img + xiaomi-jason.img in /tmp/postmarketOS-export/)
#   - Device in fastboot mode (for flash-rootfs / boot-temp)
#   - Device running with SSH (for flash-boot via dd)
#   - sshpass installed

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
EXPORT_DIR="/tmp/postmarketOS-export"
ROOTFS_IMG="$EXPORT_DIR/xiaomi-jason.img"
BOOT_IMG_ORIG="$EXPORT_DIR/boot.img"
BOOT_IMG_FIXED="/tmp/boot-r31-fixed.img"
BOOT_IMG_AUTO="/tmp/boot-r31-auto.img"
MODIFY_CMDLINE="$PROJECT_DIR/scripts/modify-bootimg-cmdline.py"
DEV_IP="172.16.42.1"
SSH_USER="user"
SSH_PASS="DEVICE_PASS_PLACEHOLDER"

# Cmdline template (no pmos.debug-shell, with stability params)
CMDLINE_BASE="plymouth.ignore-serial-consoles plymouth.prefer-fbcon loglevel=4 ignore_loglevel net.ifnames=0 earlycon console=ttyMSM0,115200 console=tty0 fbcon=nodefer consoleblank=60 cpuidle.off=1"

# Parse args
ACTION="${1:---help}"
case "$ACTION" in
    --update-uuid) DO_UPDATE_UUID=true ;;
    --flash-rootfs) DO_FLASH_ROOTFS=true ;;
    --boot-temp) DO_BOOT_TEMP=true ;;
    --flash-boot) DO_FLASH_BOOT=true ;;
    --verify) DO_VERIFY=true ;;
    --all)
        DO_UPDATE_UUID=true
        DO_FLASH_ROOTFS=true
        DO_BOOT_TEMP=true
        DO_VERIFY=true
        ;;
    --persist)
        DO_FLASH_BOOT=true
        DO_VERIFY=true
        ;;
    --help|-h|*)
        echo "Usage: $0 {--update-uuid|--flash-rootfs|--boot-temp|--flash-boot|--verify|--all|--persist}"
        echo ""
        echo "Commands:"
        echo "  --update-uuid    Update boot.img cmdline UUIDs from rootfs image"
        echo "  --flash-rootfs   Flash rootfs to userdata via fastboot"
        echo "  --boot-temp      Temporary boot via fastboot boot"
        echo "  --flash-boot     Persist boot.img via dd (requires running device with SSH)"
        echo "  --verify         Verify SSH connectivity"
        echo "  --all            Full deploy: update-uuid + flash-rootfs + boot-temp + verify"
        echo "  --persist        Persist boot: flash-boot + verify (requires running device)"
        exit 0
        ;;
esac

# === UPDATE UUID ===
if [ "${DO_UPDATE_UUID:-false}" = true ]; then
    log "=== UPDATE UUID PHASE ==="

    if [ ! -f "$ROOTFS_IMG" ]; then
        err "Rootfs image not found: $ROOTFS_IMG"
        err "Run: pmbootstrap export"
        exit 1
    fi

    if [ ! -f "$BOOT_IMG_ORIG" ]; then
        err "Boot image not found: $BOOT_IMG_ORIG"
        err "Run: pmbootstrap export"
        exit 1
    fi

    log "Mounting rootfs image to get UUIDs..."
    LOOP_DEV=$(sudo losetup -Pf --show "$ROOTFS_IMG")
    log "Loop device: $LOOP_DEV"

    # Wait for partitions
    sleep 2

    BOOT_UUID=$(sudo blkid -s UUID -o value "${LOOP_DEV}p1" 2>/dev/null)
    ROOT_UUID=$(sudo blkid -s UUID -o value "${LOOP_DEV}p2" 2>/dev/null)

    log "Boot UUID: $BOOT_UUID"
    log "Root UUID: $ROOT_UUID"

    sudo losetup -d "$LOOP_DEV"

    if [ -z "$BOOT_UUID" ] || [ -z "$ROOT_UUID" ]; then
        err "Failed to get UUIDs from rootfs image"
        exit 1
    fi

    log "Updating boot.img cmdline with correct UUIDs..."
    CMDLINE="$CMDLINE_BASE pmos_boot_uuid=$BOOT_UUID pmos_root_uuid=$ROOT_UUID pmos_rootfsopts=defaults"
    python3 "$MODIFY_CMDLINE" "$BOOT_IMG_ORIG" "$BOOT_IMG_AUTO" "$CMDLINE"

    log "Fixed boot.img: $BOOT_IMG_AUTO"
    log "UPDATE UUID COMPLETE"
fi

# === FLASH ROOTFS ===
if [ "${DO_FLASH_ROOTFS:-false}" = true ]; then
    log "=== FLASH ROOTFS PHASE ==="

    log "Checking fastboot device..."
    if ! sudo fastboot devices | grep -q fastboot; then
        err "No fastboot device found!"
        err "Enter fastboot mode: power off, hold Vol- + Power"
        exit 1
    fi

    log "Flashing rootfs to userdata..."
    sudo fastboot flash userdata "$ROOTFS_IMG"

    log "FLASH ROOTFS COMPLETE"
fi

# === BOOT TEMP ===
if [ "${DO_BOOT_TEMP:-false}" = true ]; then
    log "=== BOOT TEMP PHASE ==="

    log "Checking fastboot device..."
    if ! sudo fastboot devices | grep -q fastboot; then
        err "No fastboot device found!"
        err "Enter fastboot mode: power off, hold Vol- + Power"
        exit 1
    fi

    if [ ! -f "$BOOT_IMG_AUTO" ]; then
        err "Fixed boot.img not found: $BOOT_IMG_AUTO"
        err "Run: $0 --update-uuid first"
        exit 1
    fi

    log "Booting (temporary)..."
    sudo fastboot boot "$BOOT_IMG_AUTO"

    log "BOOT TEMP COMPLETE"
fi

# === FLASH BOOT (via dd from device) ===
if [ "${DO_FLASH_BOOT:-false}" = true ]; then
    log "=== FLASH BOOT (DD) PHASE ==="

    if [ ! -f "$BOOT_IMG_AUTO" ]; then
        err "Fixed boot.img not found: $BOOT_IMG_AUTO"
        err "Run: $0 --update-uuid first"
        exit 1
    fi

    log "Checking SSH connectivity..."
    if ! ping -c 1 -W 2 "$DEV_IP" >/dev/null 2>&1; then
        err "Device not reachable at $DEV_IP"
        err "Boot device first: $0 --boot-temp"
        exit 1
    fi

    log "Transferring boot.img to device..."
    sshpass -p "$SSH_PASS" scp -o StrictHostKeyChecking=no \
        "$BOOT_IMG_AUTO" "$SSH_USER@$DEV_IP:/tmp/boot-r31-auto.img"

    log "Verifying transfer..."
    REMOTE_MD5=$(sshpass -p "$SSH_PASS" ssh -o StrictHostKeyChecking=no \
        "$SSH_USER@$DEV_IP" 'md5sum /tmp/boot-r31-auto.img' | awk '{print $1}')
    LOCAL_MD5=$(md5sum "$BOOT_IMG_AUTO" | awk '{print $1}')

    if [ "$REMOTE_MD5" != "$LOCAL_MD5" ]; then
        err "MD5 mismatch! Local: $LOCAL_MD5, Remote: $REMOTE_MD5"
        exit 1
    fi
    log "MD5 verified: $LOCAL_MD5"

    log "Backing up current boot partition..."
    sshpass -p "$SSH_PASS" ssh -o StrictHostKeyChecking=no \
        "$SSH_USER@$DEV_IP" "echo $SSH_PASS | sudo -S dd if=/dev/disk/by-partlabel/boot of=/tmp/boot-backup.img bs=4M 2>&1"

    log "Writing boot.img to boot partition via dd..."
    sshpass -p "$SSH_PASS" ssh -o StrictHostKeyChecking=no \
        "$SSH_USER@$DEV_IP" "echo $SSH_PASS | sudo -S dd if=/tmp/boot-r31-auto.img of=/dev/disk/by-partlabel/boot bs=4M 2>&1 && sync"

    log "Verifying write..."
    MAGIC=$(sshpass -p "$SSH_PASS" ssh -o StrictHostKeyChecking=no \
        "$SSH_USER@$DEV_IP" "echo $SSH_PASS | sudo -S dd if=/dev/disk/by-partlabel/boot bs=1 count=8 2>/dev/null" | xxd -p)
    if [ "$MAGIC" = "414e44524f494421" ]; then
        log "Boot partition verified: ANDROID! magic OK"
    else
        err "Boot partition verification failed! Magic: $MAGIC"
        err "Restore backup: ssh ... 'sudo dd if=/tmp/boot-backup.img of=/dev/disk/by-partlabel/boot bs=4M'"
        exit 1
    fi

    log "Rebooting device..."
    sshpass -p "$SSH_PASS" ssh -o StrictHostKeyChecking=no \
        "$SSH_USER@$DEV_IP" "echo $SSH_PASS | sudo -S reboot" || true

    log "FLASH BOOT COMPLETE"
fi

# === VERIFY ===
if [ "${DO_VERIFY:-false}" = true ]; then
    log "=== VERIFY PHASE ==="

    log "Waiting for device to come back..."
    sleep 10

    for i in $(seq 1 90); do
        if ping -c 1 -W 2 "$DEV_IP" >/dev/null 2>&1; then
            log "Device responding to ping (try $i)"
            break
        fi
        if [ $i -eq 90 ]; then
            err "Device not responding after 90s"
            exit 1
        fi
        sleep 1
    done

    log "Waiting 10s for SSH..."
    sleep 10

    log "Testing SSH..."
    if sshpass -p "$SSH_PASS" ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
        -o ConnectTimeout=10 "$SSH_USER@$DEV_IP" \
        'echo "=== SSH OK ==="; uname -r; uptime; echo "=== cpufreq ==="; for p in 0 1; do echo "policy$p: $(cat /sys/devices/system/cpu/cpufreq/policy$p/scaling_governor) cur=$(cat /sys/devices/system/cpu/cpufreq/policy$p/scaling_cur_freq)"; done' 2>&1; then
        log "VERIFY COMPLETE - All checks passed!"
    else
        err "SSH verification failed!"
        exit 1
    fi
fi

log "=== DEPLOYMENT SUCCESSFUL ==="
