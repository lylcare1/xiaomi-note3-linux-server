#!/bin/sh
# motd-status.sh (initramfs adapted)
# 功能: SSH 登录时显示系统状态
# 适配: 无 systemctl/journalctl, 用进程检查 + /proc

echo ""
echo "=============================================="
echo " Xiaomi Mi Note 3 (jason) Linux Server"
echo " Initramfs mode (busybox PID 1)"
echo "=============================================="
echo ""

# Uptime + load
uptime_str=$(uptime 2>/dev/null | sed 's/^ *//')
echo "Uptime: $uptime_str"

# Memory
mem_info=$(free -m 2>/dev/null | awk '/^Mem:/ {printf "Total: %sMB  Used: %sMB  Free: %sMB", $2, $3, $4}')
echo "Memory: $mem_info"

# Disk
disk_info=$(df -h / 2>/dev/null | awk 'NR==2 {printf "%s  Used: %s  Avail: %s", $1, $5, $4}')
echo "Disk:   $disk_info"

# Temperature
max_temp=$(cat /sys/class/thermal/thermal_zone*/temp 2>/dev/null | sort -n | tail -1)
if [ -n "$max_temp" ]; then
    temp_c=$(awk -v t="$max_temp" 'BEGIN { printf "%.1f", t/1000 }')
    echo "Temp:   ${temp_c}C (max zone)"
fi

# WiFi
wifi_state=$(ip link show wlan0 2>/dev/null | grep -o "state [A-Z]*" | awk '{print $2}')
wpa_state=$(wpa_cli -i wlan0 status 2>/dev/null | awk -F= '/^wpa_state=/ {print $2}')
wifi_ip=$(ip -4 addr show wlan0 2>/dev/null | grep -o 'inet [0-9.]*' | awk '{print $2}')
echo "WiFi:   wlan0=${wifi_state:-none} wpa=${wpa_state:-none} ip=${wifi_ip:-none}"

# USB
usb_ip=$(ip -4 addr show usb0 2>/dev/null | grep -o 'inet [0-9.]*' | awk '{print $2}')
echo "USB:    usb0 ip=${usb_ip:-none}"

# Services (process checks)
sshd_status="down"
pgrep -x sshd >/dev/null 2>&1 && sshd_status="up"
echo "SSH:    $sshd_status"

# Server daemon
daemon_status="down"
pgrep -f server-daemon.sh >/dev/null 2>&1 && daemon_status="up"
echo "Monitor daemon: $daemon_status"

# Recent warnings (from syslog if available)
if [ -f /var/log/messages ]; then
    warn_count=$(tail -200 /var/log/messages 2>/dev/null | grep -ci "WARN\|CRITICAL" 2>/dev/null)
    echo "Recent warnings: $warn_count (in last 200 syslog lines)"
fi

echo ""
