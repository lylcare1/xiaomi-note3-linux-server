#!/bin/sh
# safe-poweroff.sh - 安全关机脚本 (解决 softdog watchdog 导致 poweroff 后重启的问题)
#
# 问题: SDM660 mainline 内核 pm_power_off 未注册 + PSCI 固件 bug,
#   poweroff 后内核无法断电, softdog 30s 超时触发重启.
#   systemd 持有 /dev/watchdog0 (RuntimeWatchdogSec=30), magic close 报 Resource busy.
#
# 方案:
#   1. 设置 RuntimeWatchdogSec=0, daemon-reload, 让 systemd 释放 watchdog
#   2. magic close /dev/watchdog0 (echo V), 停止 softdog
#   3. halt (而非 poweroff, 因为 poweroff 不断电)
#   4. 设备进入 halt 状态 (CPU WFI, 无服务, 屏幕灭), 不再被 softdog 重启
#   5. 用户长按电源键 15s+ 物理断电
#
# 用法: sudo /usr/local/bin/safe-poweroff.sh

set -e

echo "[1/5] 禁用 systemd runtime watchdog (释放 /dev/watchdog0)..."
mkdir -p /etc/systemd/system.conf.d
cat > /etc/systemd/system.conf.d/no-watchdog.conf << 'CONF'
[Manager]
RuntimeWatchdogSec=0
CONF
systemctl daemon-reload
echo "    daemon-reload 完成"

echo "[2/5] 等待 systemd 释放 watchdog..."
for i in 1 2 3 4 5; do
    sleep 1
    if echo V > /dev/watchdog0 2>/dev/null; then
        echo "    watchdog 已释放 (尝试 $i)"
        break
    fi
    echo "    尝试 $i: 仍 busy, 等待..."
done

echo "[3/5] 验证 watchdog 已停止..."
WD_STATE=$(cat /sys/class/watchdog/watchdog0/state 2>/dev/null || echo "unknown")
echo "    watchdog state: $WD_STATE"
if [ "$WD_STATE" = "active" ]; then
    echo "    警告: watchdog 仍 active, 尝试强制 magic close..."
    # 最后尝试: 直接写 (可能因 systemd 释放后有短暂窗口)
    echo V > /dev/watchdog0 2>/dev/null || true
    sleep 1
    WD_STATE=$(cat /sys/class/watchdog/watchdog0/state 2>/dev/null || echo "unknown")
    echo "    watchdog state (retry): $WD_STATE"
fi

echo "[4/5] 同步文件系统..."
sync; sync; sync
echo "    sync 完成"

echo "[5/5] 执行 halt (设备将停止运行, 不再重启)..."
echo "    设备进入 halt 状态后, 请长按电源键 15 秒物理断电"
echo "    3 秒后 halt..."
sleep 3
halt -f
