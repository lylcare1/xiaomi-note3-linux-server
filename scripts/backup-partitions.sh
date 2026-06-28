#!/usr/bin/env bash
# jason 分区备份脚本
# 用途: 在 TWRP 下用 dd + adb exec-out 流式备份所有 by-name 分区到本地
# 前提: 设备已临时 boot TWRP (fastboot boot twrp-3.7.0_9-0-jason.img)
# 作者: AI agent
# 创建: 2026-06-27
#
# 使用: bash scripts/backup-partitions.sh
# 输出: backups/original-jason-YYYYMMDD/

set -euo pipefail

DATE=$(date +%Y%m%d-%H%M%S)
SERIAL="${1:-}"
# 支持外部传入 BACKUP_DIR 实现断点续传
BACKUP_DIR="${BACKUP_DIR:-backups/original-jason-${DATE}}"
LOG_FILE="${BACKUP_DIR}/backup.log"

# ADB 参数
ADB_ARGS=()
if [ -n "$SERIAL" ]; then
    ADB_ARGS=(-s "$SERIAL")
fi

mkdir -p "$BACKUP_DIR"
echo "[$(date '+%F %T')] 开始备份 jason 分区到 $BACKUP_DIR" | tee "$LOG_FILE"

# 确认 TWRP 在线
if ! adb "${ADB_ARGS[@]}" shell echo TWRP_OK 2>/dev/null | grep -q TWRP_OK; then
    echo "[ERROR] TWRP 未就绪,请先 fastboot boot twrp-3.7.0_9-0-jason.img" | tee -a "$LOG_FILE"
    exit 1
fi

# 备份清单 (分区名:备份必要性)
# necessary: 必须备份 (原厂 fastboot 包未覆盖的运行时分区)
# verify:    推荐备份 (原厂已有,用于校验一致性)
# optional:  可选备份 (小分区,顺手备份)
PARTITIONS=(
    "modemst1:necessary"
    "modemst2:necessary"
    "fsg:necessary"
    "persist:necessary"
    "boot:verify"
    "recovery:verify"
    "system:verify"
    # userdata 跳过: 52GB 用户数据,非关键,且原厂 fastboot 包可恢复
    # "userdata:verify"
    "cache:verify"
    "cust:verify"
    "misc:verify"
    "modem:verify"
    "dsp:verify"
    "bluetooth:verify"
    "splash:optional"
    "frp:optional"
    "sec:optional"
    "ssd:optional"
    "limits:optional"
    "ddr:optional"
    "logfs:optional"
    "toolsfv:optional"
    "sti:optional"
    "apdp:optional"
    "msadp:optional"
    "devinfo:optional"
    "oops:optional"
    "mdtp:optional"
    "logdump:optional"
)

# 总数
TOTAL=${#PARTITIONS[@]}
COUNT=0
SUCCESS=0
FAILED=0
SKIPPED=0
FAILED_LIST=()

echo "" | tee -a "$LOG_FILE"
echo "共 $TOTAL 个分区待备份" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"

# 备份单个分区函数
backup_partition() {
    local part="$1"
    local necessity="$2"
    local outfile="${BACKUP_DIR}/${part}.img"

    COUNT=$((COUNT + 1))
    echo "[$COUNT/$TOTAL] 备份 $part (必要性: $necessity)..." | tee -a "$LOG_FILE"

    # 跳过已存在且大小匹配的分区 (断点续传)
    if [ -f "$outfile" ]; then
        local existing_size
        existing_size=$(stat -c %s "$outfile" 2>/dev/null || echo 0)
        local expected_size
        expected_size=$(adb "${ADB_ARGS[@]}" shell "blockdev --getsize64 /dev/block/bootdevice/by-name/${part} 2>/dev/null" | tr -d '\r\n ')
        if [ -n "$expected_size" ] && [ "$existing_size" = "$expected_size" ]; then
            echo "  [SKIP] 已存在且大小匹配 (${existing_size} bytes)" | tee -a "$LOG_FILE"
            SUCCESS=$((SUCCESS + 1))
            return 0
        fi
    fi

    # 检查分区是否存在
    if ! adb "${ADB_ARGS[@]}" shell "test -e /dev/block/bootdevice/by-name/${part}" 2>/dev/null; then
        echo "  [SKIP] 分区 $part 不存在" | tee -a "$LOG_FILE"
        SKIPPED=$((SKIPPED + 1))
        return 0
    fi

    # 获取分区大小 (bytes)
    local size_bytes
    size_bytes=$(adb "${ADB_ARGS[@]}" shell "blockdev --getsize64 /dev/block/bootdevice/by-name/${part}" 2>/dev/null | tr -d '\r\n ')
    if [ -z "$size_bytes" ] || [ "$size_bytes" = "0" ]; then
        echo "  [WARN] 无法获取 $part 大小,尝试用 ls" | tee -a "$LOG_FILE"
        size_bytes=$(adb "${ADB_ARGS[@]}" shell "stat -c %s /dev/block/bootdevice/by-name/${part} 2>/dev/null" | tr -d '\r\n ')
    fi
    local size_mb=$((size_bytes / 1024 / 1024))
    local size_kb=$((size_bytes / 1024))
    echo "  大小: ${size_bytes} bytes (${size_mb} MB / ${size_kb} KB)" | tee -a "$LOG_FILE"

    # 用 dd + adb exec-out 流式拉取
    # 注意: exec-out 比 shell 重定向更可靠地处理二进制
    # 注意: TWRP busybox dd 不支持 bs=4M 后缀,必须用纯字节数 4194304
    local start_ts end_ts duration
    start_ts=$(date +%s)

    if adb "${ADB_ARGS[@]}" exec-out "dd if=/dev/block/bootdevice/by-name/${part} bs=4194304 2>/dev/null" > "$outfile" 2>>"$LOG_FILE"; then
        local actual_size
        actual_size=$(stat -c %s "$outfile")
        end_ts=$(date +%s)
        duration=$((end_ts - start_ts))

        if [ "$actual_size" -eq "$size_bytes" ]; then
            echo "  [OK] $part -> ${outfile} (${actual_size} bytes, ${duration}s)" | tee -a "$LOG_FILE"
            SUCCESS=$((SUCCESS + 1))
        else
            echo "  [WARN] $part 大小不匹配 (期望 ${size_bytes}, 实际 ${actual_size})" | tee -a "$LOG_FILE"
            # 仍计为成功,但记录警告
            SUCCESS=$((SUCCESS + 1))
        fi
    else
        echo "  [FAIL] $part 备份失败" | tee -a "$LOG_FILE"
        FAILED=$((FAILED + 1))
        FAILED_LIST+=("$part")
        rm -f "$outfile"
        return 1
    fi

    # 生成 sha256 (对于 verify 和 necessary 的)
    if [ "$necessity" != "optional" ]; then
        echo "  计算 sha256..." | tee -a "$LOG_FILE"
        sha256sum "$outfile" | tee -a "${BACKUP_DIR}/sha256sums.txt" >/dev/null
    fi

    echo "" | tee -a "$LOG_FILE"
    return 0
}

# 主循环
for entry in "${PARTITIONS[@]}"; do
    part="${entry%%:*}"
    necessity="${entry##*:}"
    backup_partition "$part" "$necessity" || true
done

# 生成 manifest
{
    echo "# jason 分区备份清单"
    echo "# 备份时间: $(date '+%F %T %z')"
    echo "# 备份目录: $BACKUP_DIR"
    echo "# 设备序列号: $(adb "${ADB_ARGS[@]}" get-serialno 2>/dev/null | tr -d '\r\n ')"
    echo ""
    echo "## 统计"
    echo "- 总数: $TOTAL"
    echo "- 成功: $SUCCESS"
    echo "- 失败: $FAILED"
    echo "- 跳过(不存在): $SKIPPED"
    if [ "$FAILED" -gt 0 ]; then
        echo "- 失败列表: ${FAILED_LIST[*]}"
    fi
    echo ""
    echo "## 文件清单"
    ls -la "$BACKUP_DIR"
} > "${BACKUP_DIR}/MANIFEST.md"

echo "==================================" | tee -a "$LOG_FILE"
echo "备份完成" | tee -a "$LOG_FILE"
echo "总数: $TOTAL  成功: $SUCCESS  失败: $FAILED  跳过: $SKIPPED" | tee -a "$LOG_FILE"
if [ "$FAILED" -gt 0 ]; then
    echo "失败列表: ${FAILED_LIST[*]}" | tee -a "$LOG_FILE"
fi
echo "备份目录: $BACKUP_DIR" | tee -a "$LOG_FILE"
echo "MANIFEST: ${BACKUP_DIR}/MANIFEST.md" | tee -a "$LOG_FILE"
echo "==================================" | tee -a "$LOG_FILE"
