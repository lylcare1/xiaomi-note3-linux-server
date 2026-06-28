#!/bin/sh
# 对应设备 /etc/profile.d/motd-status.sh
# 来源: docs/troubleshooting.md §7.10.4 (P2-4 motd 系统状态展示)
# 触发: 交互式 shell 启动时由 /etc/profile source
#
# 显示内容:
#   - 主机名 + 当前时间
#   - uptime (用 /proc/uptime 计算, busybox uptime 不支持 -p)
#   - load (1/5/15min)
#   - memory (used/total + 百分比)
#   - disk (used/total + 百分比)
#   - 最高温度 (扫描 thermal zones, 取最大值)
#   - WiFi: SSID + IP
#   - USB: IP
#   - 最近 1 小时 journal 警告 (前 3 条)
#   - timers 列表 + 常用命令

# 只在交互式 shell 中显示
case "$-" in
    *i*) ;;
    *)
        return 0 2>/dev/null || exit 0
        ;;
esac

# hostname + 时间
hostname=$(hostname)
now=$(date '+%Y-%m-%d %H:%M:%S %Z')

# uptime (用 /proc/uptime, busybox uptime 不支持 -p)
up_secs=$(awk '{print int($1)}' /proc/uptime 2>/dev/null)
up_secs="${up_secs:-0}"
up_days=$((up_secs / 86400))
up_hours=$((up_secs % 86400 / 3600))
up_mins=$((up_secs % 3600 / 60))

# load
load=$(awk '{print $1, $2, $3}' /proc/loadavg 2>/dev/null)

# memory
mem_info=$(awk '/^MemTotal:/ {total=$2} /^MemAvailable:/ {avail=$2} END {used=total-avail; pct=total>0?int(used*100/total):0; printf "%dM / %dM (%d%%)", used/1024, total/1024, pct}' /proc/meminfo 2>/dev/null)

# disk (root filesystem, -P 保证单行格式)
disk_info=$(df -hP / 2>/dev/null | awk 'NR==2 {print $3 " / " $2 " (" $5 ")"}')

# 最高温 (扫描所有 thermal zone)
max_temp=0
max_zone="unknown"
for z in /sys/class/thermal/thermal_zone*/temp; do
    [ -r "$z" ] || continue
    t=$(cat "$z" 2>/dev/null)
    [ -z "$t" ] && continue
    t_c=$(awk -v x="$t" 'BEGIN { printf "%.1f", x/1000 }')
    if awk -v a="$t_c" -v b="$max_temp" 'BEGIN { exit !(a > b) }'; then
        max_temp="$t_c"
        zone_dir=$(dirname "$z")
        max_zone=$(cat "$zone_dir/type" 2>/dev/null)
    fi
done

# WiFi SSID + IP
wifi_ssid=$(nmcli -t -f DEVICE,STATE,CONNECTION dev status 2>/dev/null | grep "^wlan0:" | awk -F: '{print $3}')
wifi_ip=$(ip -4 addr show wlan0 2>/dev/null | awk '/inet / {print $2}' | head -1)

# USB IP
usb_ip=$(ip -4 addr show usb0 2>/dev/null | awk '/inet / {print $2}' | head -1)

# 最近 1 小时 journal 警告 (前 3 条)
warnings=$(journalctl --since "1 hour ago" -p warning --no-pager -q 2>/dev/null | tail -3)

# 输出
echo "========================================"
echo " $hostname - $now"
echo "========================================"
echo " uptime : ${up_days}d ${up_hours}h ${up_mins}m"
echo " load   : $load"
echo " mem    : $mem_info"
echo " disk   : $disk_info"
echo " temp   : ${max_temp}C (${max_zone})"
echo ""
echo " Network:"
if [ -n "$wifi_ssid" ]; then
    echo "   WiFi : $wifi_ssid  IP: ${wifi_ip:-N/A}"
else
    echo "   WiFi : (not connected)  IP: ${wifi_ip:-N/A}"
fi
echo "   USB  : IP: ${usb_ip:-N/A}"
echo ""
if [ -n "$warnings" ]; then
    echo " Recent warnings (last 1h):"
    echo "$warnings" | while IFS= read -r line; do
        [ -n "$line" ] && echo "   $line"
    done
fi
echo "========================================"
