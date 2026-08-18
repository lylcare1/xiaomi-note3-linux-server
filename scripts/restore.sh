#!/bin/bash
# restore.sh - 快速恢复 Xiaomi Mi Note 3 (jason) 到已知良好状态
#
# 用途: 系统"被折腾坏了"时, 一键恢复到 2026-07-02 的可用状态
#       (r31 内核 + pmOS rootfs + WiFi/SSH 可用 + 开机即 Linux)
#
# 前提:
#   - 设备在 fastboot 模式 (关机后按住 Vol- + Power)
#   - artifacts/ 目录有备份文件 (boot-r31-20260702.img + rootfs-r31-20260702.img)
#
# 用法:
#   ./scripts/restore.sh              # 完整恢复: flash rootfs + boot temp + persist boot
#   ./scripts/restore.sh --flash-rootfs  # 只刷 rootfs
#   ./scripts/restore.sh --boot-temp     # 只临时启动
#   ./scripts/restore.sh --persist       # 持久化 boot (需设备已启动且 SSH 可达)
#
# 恢复后:
#   ssh user@172.16.42.1  # 密码: DEVICE_PASS_PLACEHOLDER

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() { echo -e "${GREEN}[$(date +%H:%M:%S)]${NC} $*"; }
warn() { echo -e "${YELLOW}[$(date +%H:%M:%S)] WARN:${NC} $*"; }
err() { echo -e "${RED}[$(date +%H:%M:%S)] ERROR:${NC} $*" >&2; }

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ARTIFACTS="$PROJECT_DIR/artifacts"

BOOT_IMG="$ARTIFACTS/boot-r31-20260702.img"
ROOTFS_IMG="$ARTIFACTS/rootfs-r31-20260702.img"
DEV_IP="172.16.42.1"
SSH_USER="user"
SSH_PASS="${DEVICE_PASS:?需 ../secrets.env}"

# 检查文件
check_files() {
    if [ ! -f "$BOOT_IMG" ]; then
        err "Boot image not found: $BOOT_IMG"
        exit 1
    fi
    if [ ! -f "$ROOTFS_IMG" ]; then
        err "Rootfs image not found: $ROOTFS_IMG"
        exit 1
    fi
    log "Boot image: $BOOT_IMG ($(du -h "$BOOT_IMG" | cut -f1))"
    log "Rootfs image: $ROOTFS_IMG ($(du -h "$ROOTFS_IMG" | cut -f1))"
}

check_fastboot() {
    if ! sudo fastboot devices | grep -q fastboot; then
        err "No fastboot device found!"
        err "Enter fastboot mode: power off, hold Vol- + Power"
        exit 1
    fi
    log "Fastboot device: $(sudo fastboot devices)"
}

check_ssh() {
    if ! ping -c 1 -W 2 "$DEV_IP" >/dev/null 2>&1; then
        err "Device not reachable at $DEV_IP"
        err "Boot device first: $0 --boot-temp"
        exit 1
    fi
}

ACTION="${1:---all}"

case "$ACTION" in
    --flash-rootfs)
        log "=== RESTORE: Flash Rootfs ==="
        check_files
        check_fastboot
        log "Flashing rootfs to userdata (this takes ~2 min for 1.4GB)..."
        sudo fastboot flash userdata "$ROOTFS_IMG"
        log "Rootfs flashed OK"
        ;;

    --boot-temp)
        log "=== RESTORE: Boot Temporary ==="
        check_files
        check_fastboot
        log "Booting (temporary, not persisted)..."
        sudo fastboot boot "$BOOT_IMG"
        log "Boot sent. Wait ~60-90s for SSH."
        log "Verify: ssh user@$DEV_IP (password: $SSH_PASS)"
        ;;

    --persist)
        log "=== RESTORE: Persist Boot Partition ==="
        check_files
        check_ssh

        log "Transferring boot.img to device..."
        sshpass -p "$SSH_PASS" scp -o StrictHostKeyChecking=no \
            "$BOOT_IMG" "$SSH_USER@$DEV_IP:/tmp/boot-r31.img"

        log "Verifying transfer (MD5)..."
        REMOTE_MD5=$(sshpass -p "$SSH_PASS" ssh -o StrictHostKeyChecking=no \
            "$SSH_USER@$DEV_IP" 'md5sum /tmp/boot-r31.img' | awk '{print $1}')
        LOCAL_MD5=$(md5sum "$BOOT_IMG" | awk '{print $1}')
        if [ "$REMOTE_MD5" != "$LOCAL_MD5" ]; then
            err "MD5 mismatch! Local: $LOCAL_MD5, Remote: $REMOTE_MD5"
            exit 1
        fi
        log "MD5 OK: $LOCAL_MD5"

        log "Writing boot.img to boot partition via dd..."
        sshpass -p "$SSH_PASS" ssh -o StrictHostKeyChecking=no \
            "$SSH_USER@$DEV_IP" "echo '$SSH_PASS' | sudo -S dd if=/tmp/boot-r31.img of=/dev/disk/by-partlabel/boot bs=4M 2>&1 && sync"

        log "Verifying write (ANDROID! magic)..."
        MAGIC=$(sshpass -p "$SSH_PASS" ssh -o StrictHostKeyChecking=no \
            "$SSH_USER@$DEV_IP" "echo '$SSH_PASS' | sudo -S dd if=/dev/disk/by-partlabel/boot bs=1 count=8 2>/dev/null" | xxd -p)
        if [ "$MAGIC" = "414e44524f494421" ]; then
            log "Boot partition verified: ANDROID! magic OK"
        else
            err "Verification failed! Magic: $MAGIC"
            err "Device may not boot. Use fastboot to restore."
            exit 1
        fi

        log "Rebooting device..."
        sshpass -p "$SSH_PASS" ssh -o StrictHostKeyChecking=no \
            "$SSH_USER@$DEV_IP" "echo '$SSH_PASS' | sudo -S reboot" || true
        log "Reboot sent. Boot partition now persisted."
        ;;

    --all)
        log "=== FULL RESTORE: r31 kernel + pmOS rootfs ==="
        check_files

        log "Step 1/3: Flash rootfs"
        check_fastboot
        log "Flashing rootfs to userdata (~2 min)..."
        sudo fastboot flash userdata "$ROOTFS_IMG"
        log "Rootfs flashed OK"

        log "Step 2/3: Boot temporary"
        log "Booting (temporary)..."
        sudo fastboot boot "$BOOT_IMG"

        log "Step 3/3: Wait for SSH, then persist boot"
        log "Waiting for device to come up (up to 120s)..."
        sleep 15
        for i in $(seq 1 120); do
            if ping -c 1 -W 2 "$DEV_IP" >/dev/null 2>&1; then
                log "Device responding (try $i)"
                break
            fi
            [ $i -eq 120 ] && { err "Device not responding after 120s"; exit 1; }
            sleep 1
        done
        sleep 10

        log "Testing SSH..."
        if ! sshpass -p "$SSH_PASS" ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
            -o ConnectTimeout=10 "$SSH_USER@$DEV_IP" 'echo SSH_OK; uname -r' 2>/dev/null; then
            err "SSH not available. Boot may have failed."
            err "Try: $0 --boot-temp to retry, or check device screen"
            exit 1
        fi

        log "Persisting boot partition..."
        "$0" --persist
        ;;

    --verify)
        log "=== VERIFY ==="
        check_ssh
        sleep 5
        sshpass -p "$SSH_PASS" ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
            -o ConnectTimeout=10 "$SSH_USER@$DEV_IP" \
            'echo "=== SSH OK ==="; uname -r; uptime; echo "=== cpufreq ==="; for p in 0 1; do echo "policy$p: $(cat /sys/devices/system/cpu/cpufreq/policy$p/scaling_governor) max=$(cat /sys/devices/system/cpu/cpufreq/policy$p/scaling_max_freq)"; done; echo "=== WiFi ==="; nmcli dev status | head -5; echo "=== IP ==="; ip -4 addr show wlan0 2>/dev/null | grep inet' 2>&1
        ;;

    *)
        echo "Usage: $0 {--all|--flash-rootfs|--boot-temp|--persist|--verify}"
        echo ""
        echo "Commands:"
        echo "  --all           Full restore: flash rootfs + boot temp + persist boot"
        echo "  --flash-rootfs  Only flash rootfs to userdata (needs fastboot)"
        echo "  --boot-temp     Only temporary boot (needs fastboot)"
        echo "  --persist       Persist boot.img to boot partition (needs SSH)"
        echo "  --verify        Verify SSH + cpufreq + WiFi"
        echo ""
        echo "Recovery files in artifacts/:"
        echo "  boot-r31-20260702.img      - r31 boot image (UUID correct)"
        echo "  rootfs-r31-20260702.img    - pmOS rootfs image (1.4GB)"
        echo "  boot-partition-backup-20260702.img - boot partition full dump (64MB)"
        echo ""
        echo "After restore: ssh user@172.16.42.1 (password: $SSH_PASS)"
        exit 0
        ;;
esac

log "=== RESTORE COMPLETE ==="
