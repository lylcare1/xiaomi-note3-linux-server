#!/bin/sh
# charge-guard.sh — 电池磁滞充电控制 (电池保养核心)
# 原理: qcom-smbx-charger 的 status 属性暴露 CHG_EN 充电使能位 (postmarketOS 补丁)
#   echo 0 > /sys/class/power_supply/pm660-charger/status  → 停止充电 (电池供电, USB 网络不受影响)
#   echo 1 > ...                                          → 恢复充电
# 规则: cap >= HIGH (60%) → 停充;  cap <= LOW (40%) → 恢复充电;  中间 → 保持当前状态
# 频率: 2min (charge-guard.timer), 事件记 journald + 状态文件
# 保护: 无 USB 供电 (online=0) 时不做任何事; discharge-monitor 的低电关机不受影响

HIGH_CAP=60
LOW_CAP=40
CHG_CTL=/sys/class/power_supply/pm660-charger/status
BAT_CAP=/sys/class/power_supply/qcom-battery/capacity
BAT_STAT=/sys/class/power_supply/qcom-battery/status
CHG_ONLINE=/sys/class/power_supply/pm660-charger/online
STATE_FILE=/run/charge-guard-mode   # "holding" | "charging" | ""

TAG="charge-guard"

CAP=$(cat "$BAT_CAP" 2>/dev/null || echo -1)
BSTAT=$(cat "$BAT_STAT" 2>/dev/null || echo NA)
ONLINE=$(cat "$CHG_ONLINE" 2>/dev/null || echo 0)
MODE=$(cat "$STATE_FILE" 2>/dev/null || echo "")

# 异常读数直接退出, 不做动作
[ "$CAP" -lt 0 ] && exit 0
# 无外部供电 (纯电池运行): 确保充电使能 (插回电即充), 但不反复写
if [ "$ONLINE" = "0" ]; then
    if [ "$MODE" != "passive" ]; then
        echo 1 > "$CHG_CTL" 2>/dev/null
        echo "passive" > "$STATE_FILE"
        logger -t "$TAG" "no external power, charge-enable armed (passive)"
    fi
    exit 0
fi

# USB 在线, 磁滞判定
if [ "$CAP" -ge "$HIGH_CAP" ]; then
    if [ "$MODE" != "holding" ]; then
        echo 0 > "$CHG_CTL" 2>/dev/null || { logger -t "$TAG" "ERROR write CHG_CTL failed"; exit 1; }
        echo "holding" > "$STATE_FILE"
        logger -t "$TAG" "cap=${CAP}% >= ${HIGH_CAP}%, charging STOPPED (battery care)"
    fi
elif [ "$CAP" -le "$LOW_CAP" ]; then
    if [ "$MODE" != "charging" ]; then
        echo 1 > "$CHG_CTL" 2>/dev/null || { logger -t "$TAG" "ERROR write CHG_CTL failed"; exit 1; }
        echo "charging" > "$STATE_FILE"
        logger -t "$TAG" "cap=${CAP}% <= ${LOW_CAP}%, charging RESUMED"
    fi
fi
# 40% < cap < 60%: 磁滞区间, 保持当前状态, 不动作

exit 0
