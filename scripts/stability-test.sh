#!/bin/bash
# stability-test.sh — 30-min stability monitor for jason Linux server
# Runs 30 samples at 60s intervals via SSH (WiFi preferred, USB fallback)
# Logs to /home/lyl/Documents/system/XiaoMiNote3/logs/stability-test.log

LOG="/home/lyl/Documents/system/XiaoMiNote3/logs/stability-test.log"
mkdir -p "$(dirname "$LOG")"

SAMPLES=30
INTERVAL=60

echo "=== Stability Test Started $(date) ===" | tee "$LOG"
echo "Samples: $SAMPLES, Interval: ${INTERVAL}s, Duration: $((SAMPLES * INTERVAL / 60))min" | tee -a "$LOG"
echo "" >> "$LOG"

for i in $(seq 1 $SAMPLES); do
    TS=$(date '+%H:%M:%S')
    # Try WiFi first, fall back to USB
    OUT=$(ssh -o ConnectTimeout=3 jason-wifi '
        echo "uptime=$(cut -d" " -f1-3 /proc/uptime | tr " " ",")"
        echo "load=$(cat /proc/loadavg | cut -d" " -f1-3 | tr " " ",")"
        echo "mem=$(awk "/^MemTotal/{t=\$2}/^MemFree/{f=\$2}/^MemAvailable/{a=\$2}END{print (t-a)/1024\"/\"t/1024\"MB\"}" /proc/meminfo)"
        echo "temp=$(cat /sys/class/thermal/thermal_zone*/temp 2>/dev/null | sort -rn | head -1 | awk "{printf \"%d.%d\", \$1/1000, (\$1%1000)/100}")"
        echo "wlan0=$(ip -4 addr show wlan0 2>/dev/null | grep -o "inet [0-9.]*" | awk "{print \$2}" || echo DOWN)"
        echo "usb0=$(ip -4 addr show usb0 2>/dev/null | grep -o "inet [0-9.]*" | awk "{print \$2}" || echo DOWN)"
        echo "sshd=$(pgrep -f sshd >/dev/null && echo UP || echo DOWN)"
        echo "wpa=$(pgrep -f "wpa_supplicant.*wlan0" >/dev/null && echo UP || echo DOWN)"
        echo "dhcp=$(pgrep -f "udhcpc.*wlan0" >/dev/null && echo UP || echo DOWN)"
        echo "daemon=$(pgrep -f server-daemon >/dev/null && echo UP || echo DOWN)"
        echo "modem=$(cat /sys/class/remoteproc/remoteproc2/state 2>/dev/null || echo NA)"
        echo "adsp=$(cat /sys/class/remoteproc/remoteproc0/state 2>/dev/null || echo NA)"
        echo "procs=$(ls /proc | grep -c "^[0-9]")"
        echo "df=$(df / 2>/dev/null | tail -1 | awk "{print \$3\"/\"\$2\"K (\"\$5\")"}")"
    ' 2>/dev/null)
    if [ -z "$OUT" ]; then
        OUT=$(ssh -o ConnectTimeout=3 jason '
            echo "uptime=$(cut -d" " -f1-3 /proc/uptime | tr " " ",")"
            echo "load=$(cat /proc/loadavg | cut -d" " -f1-3 | tr " " ",")"
            echo "mem=$(awk "/^MemTotal/{t=\$2}/^MemAvailable/{a=\$2}END{print (t-a)/1024\"/\"t/1024\"MB\"}" /proc/meminfo)"
            echo "temp=$(cat /sys/class/thermal/thermal_zone*/temp 2>/dev/null | sort -rn | head -1 | awk "{printf \"%d.%d\", \$1/1000, (\$1%1000)/100}")"
            echo "wlan0=$(ip -4 addr show wlan0 2>/dev/null | grep -o "inet [0-9.]*" | awk "{print \$2}" || echo DOWN)"
            echo "sshd=$(pgrep -f sshd >/dev/null && echo UP || echo DOWN)"
            echo "daemon=$(pgrep -f server-daemon >/dev/null && echo UP || echo DOWN)"
            echo "NOTE=via-USB"
        ' 2>/dev/null)
    fi
    echo "[$TS] sample $i/$SAMPLES" >> "$LOG"
    echo "$OUT" | sed 's/^/  /' >> "$LOG"
    echo "" >> "$LOG"
    [ $i -lt $SAMPLES ] && sleep $INTERVAL
done

echo "=== Stability Test Complete $(date) ===" | tee -a "$LOG"
echo "Log: $LOG"
