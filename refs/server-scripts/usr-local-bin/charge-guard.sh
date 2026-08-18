#!/bin/sh
# charge-guard.sh — 电池磁滞充电控制 (电池保养核心, r3)
# 原理: 内核补丁 0010-smbx-charge-behaviour 给 qcom_smbx 驱动加了标准
#   POWER_SUPPLY_PROP_CHARGE_BEHAVIOUR 属性, 直写 PM660 真充电使能:
#   CHARGING_ENABLE_CMD(0x1042) bit0 + CHGR_CFG2(0x1051) CHG_EN_SRC_BIT(软件控制)
#   echo inhibit-charge > .../charge_behaviour → 真硬件停充
#   echo auto           > .../charge_behaviour → 恢复充电
# 规则: cap >= HIGH (60%) → 停充;  cap <= LOW (40%) → 恢复;  中间 → 保持
# 频率: 2min (charge-guard.timer), 事件记 journald + 状态文件
#
# 历史版本:
#   r1: 用 status(USBIN 挂起) + online 判断 → 2min 震荡偷充电 (已废)
#   r2: 移除 online 判断, 仍用 status — 但 USBIN suspend 在 PM660 上不停充 (test7 证伪)
#   r3 (本版): 切换到 charge_behaviour 硬件停充, 需内核 r36+ (模块 md5 5cfe139c)

HIGH_CAP=60
LOW_CAP=40
CHG_CTL=/sys/class/power_supply/pm660-charger/charge_behaviour
BAT_CAP=/sys/class/power_supply/qcom-battery/capacity
STATE_FILE=/run/charge-guard-mode   # "holding" | "charging" | ""

TAG="charge-guard"

# 属性不存在 = 模块未更新, 拒绝运行 (防止退回无停充能力的状态)
if [ ! -e "$CHG_CTL" ]; then
    logger -t "$TAG" "ERROR charge_behaviour missing (need qcom_smbx r36+), no-op"
    exit 1
fi

CAP=$(cat "$BAT_CAP" 2>/dev/null || echo -1)
MODE=$(cat "$STATE_FILE" 2>/dev/null || echo "")

# 异常读数直接退出, 不做动作
[ "$CAP" -lt 0 ] && exit 0

# 纯容量磁滞判定
if [ "$CAP" -ge "$HIGH_CAP" ]; then
    if [ "$MODE" != "holding" ]; then
        echo inhibit-charge > "$CHG_CTL" 2>/dev/null || { logger -t "$TAG" "ERROR write charge_behaviour failed"; exit 1; }
        echo "holding" > "$STATE_FILE"
        logger -t "$TAG" "cap=${CAP}% >= ${HIGH_CAP}%, charging STOPPED (hw inhibit, battery care)"
    fi
elif [ "$CAP" -le "$LOW_CAP" ]; then
    if [ "$MODE" != "charging" ]; then
        echo auto > "$CHG_CTL" 2>/dev/null || { logger -t "$TAG" "ERROR write charge_behaviour failed"; exit 1; }
        echo "charging" > "$STATE_FILE"
        logger -t "$TAG" "cap=${CAP}% <= ${LOW_CAP}%, charging RESUMED"
    fi
fi
# 40% < cap < 60%: 磁滞区间, 保持当前状态, 不动作

exit 0
