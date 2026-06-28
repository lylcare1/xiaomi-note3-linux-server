#!/bin/sh
# 对应设备 /usr/local/bin/apk-update-check.sh
# 来源: docs/troubleshooting.md §7.9.1 (P1-1 APK 自动更新通知)
# 频率: 24h (apk-update-check.timer)
# 功能: 检查 apk 更新, 不自动升级, 安全包更新记 CRITICAL
# 日志: logger -t apk-update-check
#
# 安全相关包: openssl openssh glibc busybox linux- systemd chrony sudo

TAG="apk-update-check"
PENDING_FILE="/run/apk-pending-updates"

# 安全相关包列表
SECURITY_PKGS="openssl openssh glibc busybox linux- systemd chrony sudo"

# apk update (静默, 只在失败时记录)
if ! apk update -q >/dev/null 2>&1; then
    logger -t "$TAG" "WARN apk update failed (network or repository issue)"
    exit 1
fi

# 列出可升级包
upgradable=$(apk list --upgradable 2>/dev/null)

if [ -z "$upgradable" ]; then
    logger -t "$TAG" "system is up-to-date"
    rm -f "$PENDING_FILE"
    exit 0
fi

# 写入待升级列表到文件
echo "$upgradable" > "$PENDING_FILE"

# 统计待升级包数量
count=$(printf '%s\n' "$upgradable" | grep -c '.')
logger -t "$TAG" "$count pending updates, see $PENDING_FILE"

# 检查安全相关包是否有更新
critical_found=0
for pkg in $SECURITY_PKGS; do
    # apk list --upgradable 输出每行以 "包名-版本" 开头
    if echo "$upgradable" | grep -q "^${pkg}"; then
        logger -t "$TAG" "CRITICAL security package $pkg has update"
        critical_found=1
    fi
done

if [ "$critical_found" -eq 1 ]; then
    logger -t "$TAG" "CRITICAL security updates available, run 'apk upgrade' manually"
else
    logger -t "$TAG" "no security-related updates, manual 'apk upgrade' recommended"
fi
