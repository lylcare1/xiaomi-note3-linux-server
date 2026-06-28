#!/bin/sh
# 对应设备 /usr/local/bin/fake-rtc-save.sh
# 来源: docs/troubleshooting.md §7.9.4 (P1-4 FakeRTC 时间戳持久化)
# 频率: 30min (fake-rtc-save.timer)
# 功能: 把当前时间戳 (date +%s) 写入 /var/lib/fake-rtc-time
# 日志: logger -t fake-rtc-save
#
# 说明: PMIC RTC 不可写 (ENODEV), 关机后时间丢失. NTP 正常时不依赖此文件,
#       仅在断网启动时由 fake-rtc-restore.service 恢复时间.

TAG="fake-rtc-save"
RTC_FILE="/var/lib/fake-rtc-time"

ts=$(date +%s)
echo "$ts" > "$RTC_FILE"
logger -t "$TAG" "saved timestamp $ts ($(date))"
