#!/bin/sh
# 对应设备 /usr/local/bin/temp-monitor.sh
# 来源: docs/故障排查.md §7.9.2 (P1-2 温度监控告警)
# 频率: 5min (temp-monitor.timer)
# 功能: 扫描 12 个 thermal zone, 超阈值告警, 关键温度 sync
# 日志: logger -t temp-monitor
#
# 12 个 thermal zone: aoss/cpuss0-1/cpu0-3/pwr-cluster/gpu/pm660l/pm660/qcom-battery
# 阈值: CPU/GPU 70°C WARN / 85°C CRITICAL; 电池 55°C WARN; PMIC 80°C WARN

TAG="temp-monitor"
THERMAL_BASE="/sys/class/thermal"

max_temp=0
max_zone="unknown"
warn_count=0
crit_count=0

# 遍历所有 thermal zone
for zone_dir in "$THERMAL_BASE"/thermal_zone*; do
    [ -d "$zone_dir" ] || continue
    type_file="$zone_dir/type"
    temp_file="$zone_dir/temp"
    [ -r "$type_file" ] && [ -r "$temp_file" ] || continue

    zone_type=$(cat "$type_file" 2>/dev/null)
    temp_mc=$(cat "$temp_file" 2>/dev/null)
    [ -z "$temp_mc" ] && continue

    # 毫摄氏度 -> 摄氏度 (保留 1 位小数)
    temp_c=$(awk -v t="$temp_mc" 'BEGIN { printf "%.1f", t/1000 }')

    # 更新最高温
    if awk -v a="$temp_c" -v b="$max_temp" 'BEGIN { exit !(a > b) }'; then
        max_temp="$temp_c"
        max_zone="$zone_type"
    fi

    # 根据 zone type 确定阈值
    warn_temp=70
    crit_temp=85
    case "$zone_type" in
        *battery*)
            warn_temp=55
            crit_temp=60
            ;;
        *pm660*|*pmic*)
            warn_temp=80
            crit_temp=90
            ;;
        *)
            # CPU/GPU/aoss/cpuss 等使用默认 70/85
            warn_temp=70
            crit_temp=85
            ;;
    esac

    # 阈值比较 (浮点)
    if awk -v t="$temp_c" -v c="$crit_temp" 'BEGIN { exit !(t >= c) }'; then
        logger -t "$TAG" "CRITICAL $zone_type=${temp_c}C (>=${crit_temp}C)"
        crit_count=$((crit_count + 1))
    elif awk -v t="$temp_c" -v w="$warn_temp" 'BEGIN { exit !(t >= w) }'; then
        logger -t "$TAG" "WARN $zone_type=${temp_c}C (>=${warn_temp}C)"
        warn_count=$((warn_count + 1))
    fi
done

# 关键温度: 触发 sync 防止文件系统损坏
if [ "$crit_count" -gt 0 ]; then
    logger -t "$TAG" "CRITICAL critical temp detected, syncing filesystem"
    sync
fi

# 每次运行写最高温到 journal
logger -t "$TAG" "max_temp=${max_temp}C (${max_zone}) warn=${warn_count} crit=${crit_count}"
