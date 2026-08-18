#!/bin/sh
# discharge-monitor.sh — 电池放电监控 (USB 断开期间)
# 频率: 2min (discharge-monitor.timer)
# 数据: /var/log/monitor-logs/discharge.log
# 安全: 容量 <= LOW_CAP (默认 20%) 自动 safe-poweroff.sh 软关机保护电池
#       电压 <= LOW_MV (默认 3500mV) 同样触发

LOG=/var/log/monitor-logs/discharge.log
LOW_CAP=20
LOW_MV=3500
TS=$(date "+%Y-%m-%d %H:%M:%S")

mkdir -p /var/log/monitor-logs

CAP=$(cat /sys/class/power_supply/qcom-battery/capacity 2>/dev/null || echo -1)
STAT=$(cat /sys/class/power_supply/qcom-battery/status 2>/dev/null || echo NA)
VMICRO=$(cat /sys/class/power_supply/qcom-battery/voltage_now 2>/dev/null || echo 0)
IMICRO=$(cat /sys/class/power_supply/qcom-battery/current_now 2>/dev/null || echo 0)
MV=$((VMICRO / 1000))
MA=$((IMICRO / 1000))
# 放电时电流可能为负 (放电) — 取绝对值估功率
ABSMA=${MA#-}
MW=$((MV * ABSMA / 1000))
LOAD=$(cut -d" " -f1-3 /proc/loadavg)
MAXT=$(cat /sys/class/thermal/thermal_zone*/temp 2>/dev/null | sort -n | tail -1)
[ -n "$MAXT" ] && MAXTC=$((MAXT / 1000)) || MAXTC="NA"

echo "$TS cap=${CAP}% v=${MV}mV i=${MA}mA est=${MW}mW stat=${STAT} load=${LOAD} t=${MAXTC}C" >> "$LOG"
tail -n 3000 "$LOG" > "$LOG.tmp" 2>/dev/null && mv "$LOG.tmp" "$LOG"

# 低电量保护: 自动软关机 (写 alert 供下次开机查看)
# r2 (2026-08-18): 外部供电 (Charging/Full) 时绝不关机
# 教训: 08-18 09:26 低电 halt 后插 USB 开机, cap=1% 但 Charging,
#       r1 误触发 safe-poweroff 又关机一次 (设备 halt 态充电 3.5h 到 59% 才开机成功)
if [ "$CAP" -ge 0 ] && [ "$CAP" -le "$LOW_CAP" ]; then
  if [ "$STAT" = "Charging" ] || [ "$STAT" = "Full" ]; then
    echo "$TS LOW cap=${CAP}% but external power (${STAT}), keep running & charging" >> "$LOG"
    logger -t discharge-monitor "LOW cap=${CAP}% but ${STAT}, skip poweroff"
  else
    echo "$TS CRITICAL cap=${CAP}% <= ${LOW_CAP}%, auto safe-poweroff" >> "$LOG"
    logger -t discharge-monitor "CRITICAL battery ${CAP}%, auto safe-poweroff"
    /usr/local/bin/safe-poweroff.sh
    exit 0
  fi
fi
if [ "$MV" -gt 0 ] && [ "$MV" -le "$LOW_MV" ]; then
  if [ "$STAT" = "Charging" ] || [ "$STAT" = "Full" ]; then
    echo "$TS LOW v=${MV}mV but external power (${STAT}), keep running & charging" >> "$LOG"
    logger -t discharge-monitor "LOW v=${MV}mV but ${STAT}, skip poweroff"
  else
    echo "$TS CRITICAL v=${MV}mV <= ${LOW_MV}mV, auto safe-poweroff" >> "$LOG"
    logger -t discharge-monitor "CRITICAL voltage ${MV}mV, auto safe-poweroff"
    /usr/local/bin/safe-poweroff.sh
    exit 0
  fi
fi

# 告警档 (30%): 只提醒
if [ "$CAP" -le 30 ]; then
  logger -t discharge-monitor "WARN battery ${CAP}%"
fi
exit 0
