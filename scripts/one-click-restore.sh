#!/bin/sh
# one-click-restore.sh — 真正的一键还原: 自动检测设备状态并选恢复路径
# 用法: ./one-click-restore.sh [--mode A|B|C|D|E]
#   不带参数 = 自动检测 (SSH 通 -> A; fastboot 通 -> B; 都不通 -> 提示手动)
#   --mode E = 回原厂 Android (最后手段, 需确认)

set -u
cd "$(dirname "$0")/.." || exit 1
ROOT=$(pwd)
# 密码从 secrets.env 读取 (不入库); 无则回落到环境变量
if [ -f "$ROOT/secrets.env" ]; then . "$ROOT/secrets.env"; fi
PASS="${DEVICE_PASS:?需 secrets.env 定义 DEVICE_PASS 或 export}"
HOSTPASS="${HOST_SUDO_PASS:?需 secrets.env 定义 HOST_SUDO_PASS 或 export}"
DEV=user@172.16.42.1
SSH="sshpass -p $PASS ssh -o ConnectTimeout=8 -o PreferredAuthentications=password -o PubkeyAuthentication=no $DEV"

FS=full-system-20260818-v2   # 全系统备份目录 (v2 = r36 后基线, 权威)
MODE=""

log()  { echo "[$(date +%H:%M:%S)] $*"; }
die()  { echo "ERROR: $*"; exit 1; }

# ---------- 检测函数 ----------
check_ssh() {
    $SSH 'echo SSH_OK' 2>/dev/null | grep -q SSH_OK
}

check_fastboot_simple() {
    # 任何非空输出即认为有 fastboot 设备
    OUT=$(echo "$HOSTPASS" | sudo -S fastboot devices 2>/dev/null | grep -v "^$" | head -1)
    [ -n "$OUT" ]
}

wait_fastboot() {
    log "请在设备上操作: 关机后按住 [音量下+电源] 进 fastboot (画面出现米兔修机器人)"
    for i in $(seq 1 60); do
        check_fastboot_simple && { log "fastboot 已连接: $OUT"; return 0; }
        sleep 2
    done
    return 1
}

# ---------- 恢复路径 ----------
mode_A() {
    log "=== A: SSH 在线恢复 (脚本+timer+配置) ==="
    [ -f backups/device-state-20260818/device-state-backup.tar.gz ] || die "缺 device-state 备份包"
    sh ./scripts/restore-device-state.sh || die "restore-device-state.sh 失败"
    log "A 完成. 若仍有问题, 用 --mode A+ (全量 rootfs) 或 --mode C (重刷+恢复)"
}

mode_A_full() {
    log "=== A+: SSH 在线全量 rootfs 恢复 (full-system-20260818-v2, r36 基线) ==="
    [ -f backups/$FS/rootfs.tar.gz ] || die "缺 backups/$FS/rootfs.tar.gz"
    log "解压 268MB 备份包..."
    rm -rf /tmp/fs-restore && mkdir -p /tmp/fs-restore
    tar -xzf backups/$FS/rootfs.tar.gz -C /tmp/fs-restore || die "解压失败"
    log "推送到设备 (rsync over ssh, 可能数分钟)..."
    # v2 tar 是 ./ 根打包 (busybox tar), 解压后直接在 /tmp/fs-restore 下, 无 rootfs/ 子目录
    sshpass -p $PASS rsync -az \
      --exclude=/proc --exclude=/sys --exclude=/dev --exclude=/run --exclude=/tmp \
      --exclude=/media --exclude=/mnt --exclude=/var/cache \
      -e "ssh -o PreferredAuthentications=password -o PubkeyAuthentication=no" \
      /tmp/fs-restore/ $DEV:/ || die "rsync 失败"
    log "重启验证..."
    $SSH 'echo $PASS | sudo -S reboot'
    log "A+ 完成. 90s 后: $SSH 'uptime'"
    log "恢复后自检: $SSH 'cat /sys/class/power_supply/pm660-charger/charge_behaviour'"
    log "  预期含 [auto] inhibit-charge; 且 2min 内 journalctl -t charge-guard 有 inhibit 记录"
}

mode_B() {
    log "=== B: fastboot 恢复 boot 分区 ==="
    [ -f backups/$FS/boot/boot-partition-dd.img.gz ] || die "缺 boot dd 镜像"
    check_fastboot_simple || wait_fastboot || die "fastboot 不可达"
    gunzip -c backups/$FS/boot/boot-partition-dd.img.gz > /tmp/boot-restore.img
    log "fastboot flash boot..."
    echo "$HOSTPASS" | sudo -S fastboot flash boot /tmp/boot-restore.img || die "flash 失败"
    echo "$HOSTPASS" | sudo -S fastboot reboot
    log "B 完成. 等 90s 后测 SSH; 若仍不起, rootfs 也坏了, 用 --mode C"
}

mode_C() {
    log "=== C: 完整重装 (pmbootstrap 重刷 + 备份内容恢复) ==="
    [ -x ./scripts/deploy.sh ] || die "缺 deploy.sh"
    [ -f /tmp/postmarketOS-export/xiaomi-jason.img ] || {
        log "缺 pmOS rootfs 镜像, 先跑: pmbootstrap install && pmbootstrap export"
        log "  (或跳过重刷, 仅恢复数据: --mode B 后手动 rsync rootfs)"
        die "前置条件不满足"
    }
    check_fastboot_simple || wait_fastboot || die "fastboot 不可达"
    sh ./scripts/deploy.sh --all || die "deploy --all 失败"
    log "重刷完成, 恢复备份内容..."
    mode_A_full
}

mode_D() {
    log "=== D: WiFi/固件分区恢复 ==="
    local img=""
    [ -f backups/whyred-non-hlos-20260629/modem-whyred-20260629.bin ] && img=backups/whyred-non-hlos-20260629/modem-whyred-20260629.bin
    [ -z "$img" ] && die "缺 whyred modem 备份"
    check_fastboot_simple || wait_fastboot || die "fastboot 不可达"
    echo "$HOSTPASS" | sudo -S fastboot flash modem "$img" || die "flash modem 失败"
    echo "$HOSTPASS" | sudo -S fastboot reboot
    log "D 完成. WiFi 固件已恢复 (whyred NON-HLOS fw 1.0.0.591)"
}

mode_E() {
    log "=== E: 回原厂 Android (最后手段!) ==="
    echo "警告: 此操作丢失全部 Linux 系统与数据, 回到 MIUI. 确认请输入 yes:"
    read -r CONFIRM
    [ "$CONFIRM" = "yes" ] || die "已取消"
    [ -d jason_images_V8.5.9.0.NCHCNED_20170831.0000.00_7.1_cn ] || die "缺原厂包"
    check_fastboot_simple || wait_fastboot || die "fastboot 不可达"
    cd jason_images_V8.5.9.0.NCHCNED_20170831.0000.00_7.1_cn || die
    echo "$HOSTPASS" | sudo -S ./flash_all.sh || die "flash_all 失败"
    log "E 完成. 设备回到原厂 MIUI (modemst/persist 需按刷机指南 §1.3 恢复)"
}

# ---------- 主流程 ----------
[ $# -gt 0 ] && { [ "$1" = "--mode" ] && MODE="$2"; }

if [ -z "$MODE" ]; then
    log "自动检测设备状态..."
    if check_ssh; then
        log "SSH 可达 -> 路径 A"
        MODE=A
    elif check_fastboot_simple; then
        log "fastboot 可达 -> 路径 B"
        MODE=B
    else
        log "SSH 与 fastboot 均不可达"
        log "请检查: USB 线/接口; 或设备关机按 [音量下+电源] 进 fastboot"
        log "然后重跑: $0"
        log "若确认硬砖: $0 --mode E"
        exit 2
    fi
fi

case "$MODE" in
    A) mode_A ;;
    A+) mode_A_full ;;
    B) mode_B ;;
    C) mode_C ;;
    D) mode_D ;;
    E) mode_E ;;
    *) die "未知模式: $MODE (可选 A / A+ / B / C / D / E)" ;;
esac
