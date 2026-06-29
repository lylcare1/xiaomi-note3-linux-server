#!/bin/sh
# health-check.sh (initramfs adapted)
# 频率: 5min
# 功能: 检查 sshd/wlan0/ath10k/网关, 连续 3 次失败 (15min) 自动 reboot
# 适配: 无 systemctl/NetworkManager, 用进程检查 + wpa_supplicant

TAG="health-check"
FAIL_FILE="/run/health-check-failures"
MAX_FAILURES=3

failures=0
[ -f "$FAIL_FILE" ] && failures=$(cat "$FAIL_FILE" 2>/dev/null)
[ -z "$failures" ] && failures=0

check_failed() {
    failures=$((failures + 1))
    echo "$failures" > "$FAIL_FILE"
    logger -t "$TAG" "WARN check failed (failure $failures/$MAX_FAILURES): $1"
    if [ "$failures" -ge "$MAX_FAILURES" ]; then
        logger -t "$TAG" "CRITICAL $MAX_FAILURES consecutive failures, rebooting"
        sync
        sleep 2
        reboot
    fi
}

check_ok() {
    echo 0 > "$FAIL_FILE"
    logger -t "$TAG" "system healthy"
}

# 1. sshd 进程存在? (process name is sshd.pam, use -f for full match)
if ! pgrep -f "sshd" >/dev/null 2>&1; then
    logger -t "$TAG" "sshd not running, restarting"
    /usr/sbin/sshd.pam 2>/dev/null
    sleep 2
    if ! pgrep -f "sshd" >/dev/null 2>&1; then
        check_failed "sshd restart failed"
        exit 1
    fi
fi

# 2. wlan0 接口存在?
if ! ip link show wlan0 >/dev/null 2>&1; then
    check_failed "wlan0 interface missing (driver problem)"
    exit 1
fi
# wlan0 DOWN is OK in initramfs mode (WiFi not connected to a network)
if ! ip link show wlan0 2>/dev/null | grep -q "state UP"; then
    logger -t "$TAG" "INFO wlan0 exists but DOWN (WiFi not connected, OK in initramfs mode)"
fi

# 3. ath10k 是否 crash (检查 dmesg 最近 100 行)
if dmesg 2>/dev/null | tail -100 | grep -i "ath10k" | grep -iq "crash"; then
    check_failed "ath10k firmware crash detected in dmesg"
    exit 1
fi

# 4. 默认网关可达? (如果有网关的话; WiFi 未连接时跳过)
gw=$(ip route 2>/dev/null | awk '/default/ {print $3; exit}')
if [ -n "$gw" ]; then
    if ! ping -c 2 -W 3 "$gw" >/dev/null 2>&1; then
        logger -t "$TAG" "gateway $gw unreachable"
        check_failed "gateway $gw unreachable"
        exit 1
    fi
fi

check_ok
