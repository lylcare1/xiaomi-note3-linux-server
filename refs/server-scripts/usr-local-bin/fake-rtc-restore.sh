#!/bin/sh
# 对应设备 /usr/local/bin/fake-rtc-restore.sh
# 来源: docs/故障排查.md §7.9.4 (P1-4 FakeRTC 恢复)
# 触发: 开机时 fake-rtc-restore.service (ConditionPathExists=/var/lib/fake-rtc-time)
# 功能: 若 NTP 60s 内未同步, 从 /var/lib/fake-rtc-time 恢复时间
# 日志: logger -t fake-rtc-restore
#
# 策略: 先检查当前年份是否合理 (>=2024), 若已合理说明 NTP 已同步则退出;
#       否则等待最多 60s; 仍未同步则从文件恢复 (加 1s 补偿)

TAG="fake-rtc-restore"
RTC_FILE="/var/lib/fake-rtc-time"

# 如果当前时间已合理 (NTP 已同步), 无需恢复
current_year=$(date +%Y)
if [ "$current_year" -ge 2024 ]; then
    logger -t "$TAG" "system time reasonable (year=$current_year), NTP likely synced"
    exit 0
fi

# 等待 NTP 同步 (最多 60s = 12 次 * 5s)
i=0
while [ "$i" -lt 12 ]; do
    sleep 5
    current_year=$(date +%Y)
    if [ "$current_year" -ge 2024 ]; then
        elapsed=$((i * 5 + 5))
        logger -t "$TAG" "NTP synced within ${elapsed}s"
        exit 0
    fi
    i=$((i + 1))
done

# 60s 内未同步, 从文件恢复
if [ ! -f "$RTC_FILE" ]; then
    logger -t "$TAG" "WARN NTP not synced within 60s and $RTC_FILE not found"
    exit 1
fi

saved_ts=$(cat "$RTC_FILE" 2>/dev/null)
if [ -z "$saved_ts" ]; then
    logger -t "$TAG" "WARN $RTC_FILE is empty, cannot restore time"
    exit 1
fi

# 加 1s 补偿关机期间流逝
new_ts=$((saved_ts + 1))
date -s "@$new_ts" >/dev/null 2>&1
logger -t "$TAG" "restored time: saved_ts=$saved_ts -> $new_ts ($(date))"
