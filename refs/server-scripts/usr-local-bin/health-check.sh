#!/bin/sh
# 对应设备 /usr/local/bin/health-check.sh
# 来源: docs/故障排查.md §7.8.5 (P0-5 系统健康检查)
# 修订: r2 (2026-07-02) - 区分软/硬故障, 避免 WiFi 弱信号场景 bootloop
# 修订: r3 (2026-07-02) - WiFi radio 手动关闭时跳过 wlan0/网关检查
# 修订: r4 (2026-08-17) - 软故障到达阈值时判断 AP 环境是否离线
# 修订: r5 (2026-08-18) - 护栏增强: 扫描结果不含任何已配置 SSID 时视为
#       环境变化 (AP 改名/换路由器), 只记日志不 reboot, 防止每小时空转重启
#       教训: 2026-08-18 19:26 ChinaNet-810 AP 消失, 周围有别家 AP 可扫到,
#             r4 的 "完全无 AP" 护栏没拦住, 造成 reboot 循环 (16:37/19:26 两次)
# 频率: 5min (health-check.timer)
# 日志: logger -t health-check
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

# r5: 判断 WiFi 环境是否还有"自家用 AP"可连
# 返回 0 = 该 reboot (环境正常但连不上, 疑似驱动卡死)
# 返回 1 = 不该 reboot (环境离线/AP 变了, 重启无济于事)
wifi_env_still_valid() {
    # 电池供电不 reboot: reboot 只会更耗电
    batt_stat=$(cat /sys/class/power_supply/qcom-battery/status 2>/dev/null)
    if [ "$batt_stat" = "Discharging" ]; then
        logger -t "$TAG" "soft failures reached but on battery, skip reboot (WiFi env offline?)"
        return 1
    fi
    # 强制重扫
    scan_ssids=$(nmcli -t -f SSID dev wifi list --rescan yes 2>/dev/null | sort -u)
    # 一个 AP 都看不到 = 环境离线, 不重启
    if [ -z "$scan_ssids" ]; then
        logger -t "$TAG" "no WiFi APs visible, environment offline, skip reboot"
        return 1
    fi
    # r5 新增: 有 AP 但都不是自家的 = AP 改名/换路由器, 重启无用
    # 自家 SSID = NM 里已配置的 wifi 连接的 ssid
    configured=$(nmcli -t -f NAME,TYPE connection show 2>/dev/null \
        | grep ':802-11-wireless$' | cut -d: -f1)
    for conn in $configured; do
        want=$(nmcli -s -t -f 802-11-wireless.ssid connection show "$conn" 2>/dev/null)
        want=${want#802-11-wireless.ssid:}
        [ -z "$want" ] && continue
        if echo "$scan_ssids" | grep -qx "$want"; then
            logger -t "$TAG" "configured SSID '$want' is visible, reboot may help"
            return 0
        fi
    done
    logger -t "$TAG" "no configured SSID in scan (AP gone/renamed?), skip reboot (r5)"
    return 1
}

# 软故障: WiFi/网络波动, 不 restart NM, 缓慢 reboot
soft_fail() {
    soft_failures=$((soft_failures + 1))
    echo "$soft_failures" > "$SOFT_FAIL_FILE"
    echo 0 > "$HARD_FAIL_FILE"
    logger -t "$TAG" "SOFT fail ($soft_failures/$MAX_SOFT_FAILURES): $1"
    if [ "$soft_failures" -ge "$MAX_SOFT_FAILURES" ]; then
        if wifi_env_still_valid; then
            logger -t "$TAG" "WARNING $MAX_SOFT_FAILURES soft failures, rebooting to recover WiFi"
            sync
            sleep 2
            reboot
        else
            # 不重启, 计数清零但保留一条日志轨迹 (每轮到阈值记一次)
            echo 0 > "$SOFT_FAIL_FILE"
            exit 1
        fi
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
