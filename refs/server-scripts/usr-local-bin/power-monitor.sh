#!/bin/sh
# power-monitor.sh — 功耗监控 (RRADC USB 输入侧) r1
# 数据: /var/log/monitor-logs/power.log (每小时一行)
# 来源: pm660-rradc iio device0, usbin_v/usbin_i
# 换算: v_uv = raw*19531.25, i_ua = raw*4604.49; mW = v*i/1e6

LOG=/var/log/monitor-logs/power.log
D=/sys/bus/iio/devices/iio:device0
TS=$(date "+%Y-%m-%d %H:%M:%S")

if [ ! -d "$D" ]; then
  echo "$TS ERROR rradc not found" >> "$LOG"
  exit 1
fi

# 采样 5 次取中值, 降低抖动
i=0; VSUM=0; ISUM=0
while [ $i -lt 5 ]; do
  v=$(cat $D/in_voltage0_raw 2>/dev/null || echo 0)
  c=$(cat $D/in_current0_raw 2>/dev/null || echo 0)
  VSUM=$((VSUM + v)); ISUM=$((ISUM + c))
  sleep 1
  i=$((i+1))
done
V=$((VSUM / 5)); I=$((ISUM / 5))

# 换算 (uV/uA -> mV/mA 保留 1 位小数用整数近似)
VUV=$(( V * 19531 + V / 4 ))   # ~19531.25 uV
IUA=$(( I * 4604 + I / 2 ))    # ~4604.49 uA
MV=$(( VUV / 1000 ))
MA=$(( IUA / 1000 ))
MW=$(( MV * MA / 1000 ))       # mW

# CPU 负载与最高温度 (关联上下文)
LOAD=$(cut -d" " -f1 /proc/loadavg)
MAXT=$(cat /sys/class/thermal/thermal_zone*/temp 2>/dev/null | sort -n | tail -1)
[ -n "$MAXT" ] && MAXTC=$((MAXT / 1000)) || MAXTC="NA"

# 电池状态 (充电循环观察)
CAP=$(cat /sys/class/power_supply/qcom-battery/capacity 2>/dev/null || echo NA)
BSTAT=$(cat /sys/class/power_supply/qcom-battery/status 2>/dev/null || echo NA)

mkdir -p /var/log/monitor-logs
echo "$TS usbin=${MV}mV/${MA}mA pwr=${MW}mW load=${LOAD} maxtemp=${MAXTC}C batt=${CAP}%/${BSTAT}" >> "$LOG"

# trim 到 2000 行
tail -n 2000 "$LOG" > "$LOG.tmp" 2>/dev/null && mv "$LOG.tmp" "$LOG"

# 告警: 超过 3W (异常)
if [ "$MW" -gt 3000 ]; then
  logger -t power-monitor "WARN usb power ${MW}mW > 3000mW"
fi
exit 0
