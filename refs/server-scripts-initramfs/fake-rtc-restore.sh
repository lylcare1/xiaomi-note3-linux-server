#!/bin/sh
# fake-rtc-restore.sh (initramfs adapted)
# 功能: 启动时从 /var/lib/fake-rtc-time 恢复时间 (如果 NTP 未同步)
# 由 server-daemon.sh 启动时调用

RTC_FILE="/var/lib/fake-rtc-time"

if [ ! -f "$RTC_FILE" ]; then
    logger -t fake-rtc-restore "no saved timestamp, skipping"
    exit 0
fi

saved_ts=$(cat "$RTC_FILE" 2>/dev/null)
[ -z "$saved_ts" ] && exit 0

# 检查当前时间是否合理 (2024 年以后认为 NTP 已同步)
current_year=$(date +%Y 2>/dev/null)
if [ "$current_year" -gt 2024 ] 2>/dev/null; then
    logger -t fake-rtc-restore "time already set (year=$current_year), skipping"
    exit 0
fi

# 恢复时间
logger -t fake-rtc-restore "restoring time from timestamp $saved_ts"
date -s "@$saved_ts" 2>/dev/null
logger -t fake-rtc-restore "time set to $(date)"
