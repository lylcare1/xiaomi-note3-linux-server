#!/bin/sh
# 对应设备 /usr/local/bin/health-check.sh
# 来源: docs/troubleshooting.md §7.8.5 (P0-5 系统健康检查)
# 频率: 5min (health-check.timer)
# 功能: 检查 sshd/NM/wlan0/ath10k/网关, 连续 3 次失败 (15min) 自动 reboot
# 日志: logger -t health-check
#
# 检查项:
#   1. sshd 服务是否 active, 失败则 restart
#   2. NetworkManager 服务是否 active, 失败则 restart
#   3. wlan0 接口是否 up, 失败则 restart NetworkManager
#   4. ath10k 是否 crash (检查 dmesg 最近 100 行)
#   5. 默认网关是否可达 (ping 2 次, 超时 3s), 失败则 restart NetworkManager

TAG="health-check"
FAIL_FILE="/run/health-check-failures"
MAX_FAILURES=3

failures=0
[ -f "$FAIL_FILE" ] && failures=$(cat "$FAIL_FILE" 2>/dev/null)
[ -z "$failures" ] && failures=0

# 失败处理: 递增计数器, 达到阈值 reboot
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

# 成功处理: 计数器清零
check_ok() {
    echo 0 > "$FAIL_FILE"
    logger -t "$TAG" "system healthy"
}

# 1. sshd 服务 active?
if ! systemctl is-active --quiet sshd 2>/dev/null; then
    logger -t "$TAG" "sshd not active, restarting"
    systemctl restart sshd
    sleep 2
    if ! systemctl is-active --quiet sshd 2>/dev/null; then
        check_failed "sshd restart failed"
        exit 1
    fi
fi

# 2. NetworkManager 服务 active?
if ! systemctl is-active --quiet NetworkManager 2>/dev/null; then
    logger -t "$TAG" "NetworkManager not active, restarting"
    systemctl restart NetworkManager
    sleep 5
    if ! systemctl is-active --quiet NetworkManager 2>/dev/null; then
        check_failed "NetworkManager restart failed"
        exit 1
    fi
fi

# 3. wlan0 接口 up?
if ! ip link show wlan0 2>/dev/null | grep -q "state UP"; then
    logger -t "$TAG" "wlan0 down, restarting NetworkManager"
    systemctl restart NetworkManager
    sleep 5
    if ! ip link show wlan0 2>/dev/null | grep -q "state UP"; then
        check_failed "wlan0 still down after NM restart"
        exit 1
    fi
fi

# 4. ath10k 是否 crash (检查 dmesg 最近 100 行)
if dmesg 2>/dev/null | tail -100 | grep -i "ath10k" | grep -iq "crash"; then
    check_failed "ath10k firmware crash detected in dmesg"
    exit 1
fi

# 5. 默认网关可达? (ping 2 次, 超时 3s)
gw=$(ip route 2>/dev/null | awk '/default/ {print $3; exit}')
if [ -z "$gw" ]; then
    check_failed "no default gateway"
    exit 1
fi

if ! ping -c 2 -W 3 "$gw" >/dev/null 2>&1; then
    logger -t "$TAG" "gateway $gw unreachable, restarting NetworkManager"
    systemctl restart NetworkManager
    sleep 5
    if ! ping -c 2 -W 3 "$gw" >/dev/null 2>&1; then
        check_failed "gateway $gw still unreachable"
        exit 1
    fi
fi

check_ok
