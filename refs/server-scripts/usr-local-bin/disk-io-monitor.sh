#!/bin/sh
# 对应设备 /usr/local/bin/disk-io-monitor.sh
# 来源: docs/troubleshooting.md §7.10.3 (P2-3 disk I/O 统计)
# 频率: 10min (disk-io-monitor.timer)
# 功能: 从 /proc/diskstats 读 mmcblk1 (eMMC) 统计, 转 sectors -> MB, in_flight > 50 WARN
# 日志: logger -t disk-io-monitor
#
# /proc/diskstats 字段 (mmcblk1 行):
#   major minor name reads_done reads_merged sectors_read read_ms
#   writes_done writes_merged sectors_written write_ms in_flight io_ms ...
# sector = 512 字节

TAG="disk-io-monitor"

# 精确匹配 mmcblk1 (不匹配 mmcblk1p1/p70 等分区)
line=$(awk '$3 == "mmcblk1" {print; exit}' /proc/diskstats 2>/dev/null)

if [ -z "$line" ]; then
    logger -t "$TAG" "WARN mmcblk1 not found in /proc/diskstats"
    exit 1
fi

# 解析字段
reads_done=$(echo "$line" | awk '{print $4}')
sectors_read=$(echo "$line" | awk '{print $6}')
writes_done=$(echo "$line" | awk '{print $8}')
sectors_written=$(echo "$line" | awk '{print $10}')
in_flight=$(echo "$line" | awk '{print $12}')
io_ms=$(echo "$line" | awk '{print $13}')

# sectors (512B) -> MB
read_mb=$(awk -v s="$sectors_read" 'BEGIN { printf "%.2f", s*512/1048576 }')
write_mb=$(awk -v s="$sectors_written" 'BEGIN { printf "%.2f", s*512/1048576 }')

logger -t "$TAG" "disk=mmcblk1 reads=$reads_done (${read_mb}MB) writes=$writes_done (${write_mb}MB) in_flight=$in_flight io_ms=$io_ms"

if [ "$in_flight" -gt 50 ]; then
    logger -t "$TAG" "WARN mmcblk1 in_flight=$in_flight > 50 (disk bottleneck)"
fi
