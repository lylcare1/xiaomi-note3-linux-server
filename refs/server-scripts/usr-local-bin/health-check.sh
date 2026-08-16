#!/bin/sh
# 对应设备 /usr/local/bin/health-check.sh
# 来源: docs/故障排查.md §7.8.5 (P0-5 系统健康检查)
# 修订: r2 (2026-07-02) - 区分软/硬故障, 避免 WiFi 弱信号场景 bootloop
# 修订: r3 (2026-07-02) - WiFi radio 手动关闭时跳过 wlan0/网关检查
# 频率: 5min (health-check.timer)
# 日志: logger -t health-check
#
# 故障分级 (r2 关键改动):
#   硬故障 (3 次 = 15min reboot): sshd/NM 服务崩溃, ath10k firmware crash
#   软故障 (12 次 = 60min reboot): wlan0 down, 网关不可达
#     - WiFi 信号弱/关联慢是正常波动, 不应快速 reboot
#     - 软故障不 restart NM (避免打断 NM 的关联重试节奏)
#     - 给 NM 60min 自行恢复窗口, 仍持续故障才 reboot
#
# WiFi radio off 处理 (r3):
#   用户主动关闭 WiFi (nmcli radio wifi off) 时, wlan0 必然 down 且无网关
#   这是用户意图, 不是故障, 跳过 wlan0/网关检查, 直接 check_ok
#   这样可以在 WiFi 关闭状态下安全启用 health-check.timer
#
# 历史教训 (r1 -> r2):
#   r1 把 wlan0 down 当硬故障 + 5s 内 restart NM, 背包弱信号场景
#   NM 反复重启打断关联, 3 次 (15min) 必 reboot, 形成 bootloop

TAG="health-check"
HARD_FAIL_FILE="/run/health-check-hard-failures"
SOFT_FAIL_FILE="/run/health-check-soft-failures"
MAX_HARD_FAILURES=3    # 硬故障: 15min
MAX_SOFT_FAILURES=12   # 软故障: 60min (给 WiFi 充分重试时间)

read_counter() {
    [ -f "$1" ] && cat "$1" 2>/dev/null || echo 0
}

hard_failures=$(read_counter "$HARD_FAIL_FILE")
soft_failures=$(read_counter "$SOFT_FAIL_FILE")
[ -z "$hard_failures" ] && hard_failures=0
[ -z "$soft_failures" ] && soft_failures=0

# 硬故障: 服务崩溃/驱动 crash, 快速 reboot
hard_fail() {
    hard_failures=$((hard_failures + 1))
    echo "$hard_failures" > "$HARD_FAIL_FILE"
    echo 0 > "$SOFT_FAIL_FILE"
    logger -t "$TAG" "HARD fail ($hard_failures/$MAX_HARD_FAILURES): $1"
    if [ "$hard_failures" -ge "$MAX_HARD_FAILURES" ]; then
        logger -t "$TAG" "CRITICAL $MAX_HARD_FAILURES hard failures, rebooting"
        sync
        sleep 2
        reboot
    fi
}

# 软故障: WiFi/网络波动, 不 restart NM, 缓慢 reboot
soft_fail() {
    soft_failures=$((soft_failures + 1))
    echo "$soft_failures" > "$SOFT_FAIL_FILE"
    echo 0 > "$HARD_FAIL_FILE"
    logger -t "$TAG" "SOFT fail ($soft_failures/$MAX_SOFT_FAILURES): $1"
    if [ "$soft_failures" -ge "$MAX_SOFT_FAILURES" ]; then
        # r4 (2026-08-17): 到达阈值先判断是否值得/安全 reboot
        # 教训: 2026-08-16 23:58 路由器被关闭 60min, 触发 12 次软故障 reboot,
        #       误伤电池放电测试 (r3 只处理了设备侧 radio off, 没料到 AP 侧消失)
        batt_stat=$(cat /sys/class/power_supply/qcom-battery/status 2>/dev/null)
        if [ "$batt_stat" = "Discharging" ]; then
            # 电池供电时不 reboot: reboot 只会更耗电, 且路由器关闭场景重启无济于事
            echo 0 > "$SOFT_FAIL_FILE"
            logger -t "$TAG" "soft failures reached but on battery, skip reboot (WiFi env offline?)"
            exit 1
        fi
        # 有外部供电: 扫描确认 WiFi 环境是否有 AP 可连
        if ! nmcli -t -f SSID dev wifi list --rescan yes 2>/dev/null | grep -q .; then
            # 一个 AP 都看不到 = 环境离线 (路由器关了), 不是驱动卡死, 不重启
            # (真驱动卡死通常伴随 ath10k crash -> 走硬故障路径, 不受此影响)
            echo 0 > "$SOFT_FAIL_FILE"
            logger -t "$TAG" "no WiFi APs visible, environment offline, skip reboot"
            exit 1
        fi
        logger -t "$TAG" "WARNING $MAX_SOFT_FAILURES soft failures, rebooting to recover WiFi"
        sync
        sleep 2
        reboot
    fi
}

# 成功: 两个计数器都清零
check_ok() {
    echo 0 > "$HARD_FAIL_FILE"
    echo 0 > "$SOFT_FAIL_FILE"
    logger -t "$TAG" "system healthy"
}

# 1. sshd 服务 active? (硬故障)
if ! systemctl is-active --quiet sshd 2>/dev/null; then
    logger -t "$TAG" "sshd not active, restarting"
    systemctl restart sshd
    sleep 2
    if ! systemctl is-active --quiet sshd 2>/dev/null; then
        hard_fail "sshd restart failed"
        exit 1
    fi
fi

# 2. NetworkManager 服务 active? (硬故障)
if ! systemctl is-active --quiet NetworkManager 2>/dev/null; then
    logger -t "$TAG" "NetworkManager not active, restarting"
    systemctl restart NetworkManager
    sleep 5
    if ! systemctl is-active --quiet NetworkManager 2>/dev/null; then
        hard_fail "NetworkManager restart failed"
        exit 1
    fi
fi

# 3. wlan0 接口 up? (软故障 - 信号弱/关联慢是正常的, 不 restart NM)
#    但若 WiFi radio 被手动关闭 (r3), 跳过 wlan0/网关检查
wifi_radio=$(nmcli radio wifi 2>/dev/null)
if [ "$wifi_radio" = "disabled" ]; then
    # WiFi 被用户主动关闭, 不算故障, 跳过 WiFi 相关检查
    logger -t "$TAG" "WiFi radio off (user disabled), skipping wlan0/gateway checks"
    check_ok
    exit 0
fi

if ! ip link show wlan0 2>/dev/null | grep -q "state UP"; then
    soft_fail "wlan0 down (WiFi not associated, NM will retry)"
    exit 1
fi

# 4. ath10k 是否 crash (检查 dmesg 最近 100 行) - 硬故障
if dmesg 2>/dev/null | tail -100 | grep -i "ath10k" | grep -iq "crash"; then
    hard_fail "ath10k firmware crash detected in dmesg"
    exit 1
fi

# 5. 默认网关可达? (软故障 - 网络抖动是正常的, 不 restart NM)
gw=$(ip route 2>/dev/null | awk '/default/ {print $3; exit}')
if [ -z "$gw" ]; then
    soft_fail "no default gateway (WiFi not connected yet)"
    exit 1
fi

if ! ping -c 2 -W 3 "$gw" >/dev/null 2>&1; then
    soft_fail "gateway $gw unreachable (network fluctuation)"
    exit 1
fi

check_ok
