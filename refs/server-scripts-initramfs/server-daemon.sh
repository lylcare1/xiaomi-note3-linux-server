#!/bin/sh
# server-daemon.sh - initramfs mode server monitoring scheduler
# 替代 8 个 systemd timers, 用 busybox loop 调度
# 由 init_2nd.sh 通过 chroot /sysroot 启动
#
# 调度表 (interval 秒):
#   health-check     300   (5min)
#   temp-monitor     300   (5min)
#   net-monitor      300   (5min)
#   disk-io-monitor  600   (10min)
#   fake-rtc-save    1800  (30min)
#   apk-update-check 86400 (24h)
#   fsck-check       604800 (7d) - 只读 e2fsck
#   config-backup    604800 (7d)

LOG_TAG="server-daemon"
SCRIPT_DIR="/usr/local/bin"
STATE_DIR="/run/server-daemon"
mkdir -p "$STATE_DIR"

# 任务定义: "name interval_seconds"
TASKS="
health-check:300
temp-monitor:300
net-monitor:300
disk-io-monitor:600
fake-rtc-save:1800
apk-update-check:86400
config-backup:604800
"

# fsck-check 单独处理 (需要 root + 只读)
FSCK_INTERVAL=604800

logger -t "$LOG_TAG" "started (PID $$)"

# Bring up Bluetooth (WCN3990 via UART, hci0)
# Idempotent: safe to call on every daemon restart
if [ -x /usr/local/bin/bt-start.sh ] && [ -d /sys/class/bluetooth ]; then
    /usr/local/bin/bt-start.sh >/dev/null 2>&1 &
    logger -t "$LOG_TAG" "bt-start.sh triggered in background"
fi

# 初始化: 首次启动后等 60s 再开始 (让 modem/wifi 稳定)
sleep 60

# fsck-check 需要 root 且只读, 直接在这里实现
run_fsck_check() {
    logger -t "fsck-check" "running read-only e2fsck on rootfs"
    # rootfs 是 /dev/loop0p2
    if [ -b /dev/loop0p2 ]; then
        result=$(e2fsck -f -n /dev/loop0p2 2>&1)
        rc=$?
        if [ $rc -eq 0 ]; then
            logger -t "fsck-check" "rootfs clean"
        else
            logger -t "fsck-check" "WARN e2fsck rc=$rc: $(echo "$result" | tail -3)"
        fi
    fi
}

# 主循环
while true; do
    now=$(date +%s)

    # 遍历任务
    echo "$TASKS" | while IFS=: read -r name interval; do
        [ -z "$name" ] && continue

        script="$SCRIPT_DIR/$name.sh"
        [ -x "$script" ] || continue

        state_file="$STATE_DIR/$name.last"
        last_run=0
        [ -f "$state_file" ] && last_run=$(cat "$state_file" 2>/dev/null)
        [ -z "$last_run" ] && last_run=0

        elapsed=$((now - last_run))
        if [ "$elapsed" -ge "$interval" ]; then
            logger -t "$LOG_TAG" "running $name (interval=${interval}s elapsed=${elapsed}s)"
            "$script" >/dev/null 2>&1 &
            # 不等待, 让任务并行
            echo "$now" > "$state_file"
        fi
    done

    # fsck-check
    fsck_state="$STATE_DIR/fsck-check.last"
    fsck_last=0
    [ -f "$fsck_state" ] && fsck_last=$(cat "$fsck_state" 2>/dev/null)
    fsck_elapsed=$((now - fsck_last))
    if [ "$fsck_elapsed" -ge "$FSCK_INTERVAL" ]; then
        run_fsck_check &
        echo "$now" > "$fsck_state"
    fi

    # 每 60s 检查一次
    sleep 60
done
