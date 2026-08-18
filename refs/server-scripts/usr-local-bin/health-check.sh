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
# 修订: r6 (2026-08-18) - ath10k 固件挂死自愈: wlan0 down 且扫描失败时
#       自动 rmmod+modprobe ath10k_snoc (实测 8s 恢复), 避免走到 reboot;
#       教训: 2026-08-18 19:51 新路由器 泽川源科技 触发 WCN3990 固件崩溃循环
#             (WMI keepalive -108 -> firmware crashed -> recover 不完全),
#             扫描报 ret=-100, 只有重载驱动才能救
# 频率: 5min (health-check.timer)
# 日志: logger -t health-check
TAG="health-check"
HARD_FAIL_FILE="/run/health-check-hard-failures"
SOFT_FAIL_FILE="/run/health-check-soft-failures"
RELOAD_FILE="/run/health-check-ath10k-reloads"
MAX_HARD_FAILURES=3    # 硬故障: 15min
MAX_SOFT_FAILURES=12   # 软故障: 60min (给 WiFi 充分重试时间)
MAX_ATH10K_RELOADS=6   # r6: 1小时内最多自愈重载 6 次 (30min), 超过说明重载无效, 回落 reboot 判定

read_counter() {
    [ -f "$1" ] && cat "$1" 2>/dev/null || echo 0
}

hard_failures=$(read_counter "$HARD_FAIL_FILE")
soft_failures=$(read_counter "$SOFT_FAIL_FILE")
ath_reloads=$(read_counter "$RELOAD_FILE")
[ -z "$hard_failures" ] && hard_failures=0
[ -z "$soft_failures" ] && soft_failures=0
[ -z "$ath_reloads" ] && ath_reloads=0

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
    # r6: 扫描彻底失败 (空输出 + ret=-100 类错误) = 驱动挂死, 交给自愈
    #     (r5 会把这种情况误判成"环境离线", 但驱动挂死只有 reboot/重载能救)
    # 一个 AP 都看不到 + dmesg 有 firmware crashed = 驱动挂死特征
    if [ -z "$scan_ssids" ]; then
        if dmesg | tail -200 | grep -q "ath10k.*firmware crashed"; then
            logger -t "$TAG" "scan empty + ath10k crash in dmesg = driver wedged"
            return 0
        fi
        logger -t "$TAG" "no WiFi APs visible, environment offline, skip reboot"
        return 1
    fi
    # r5: 有 AP 但都不是自家的 = AP 改名/换路由器, 重启无用
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

# r6: ath10k 固件挂死自愈 — 重载驱动 (实测 8s 恢复, 不断 USB 网络)
# r7 (2026-08-18): 重载后 wlan0 未回归 = QMI/remoteproc 深度卡死
#       (dmesg: msa info req rejected: 90), 重载无效, 立即 reboot 兜底;
#       教训: 20:09/20:14 两次重载均 error 90, 白等 30min+ 才走到 reboot
# 成功条件: wlan0 down 且 (扫描失败 或 dmesg 最近有 ath10k crash)
ath10k_selfheal() {
    if [ "$ath_reloads" -ge "$MAX_ATH10K_RELOADS" ]; then
        logger -t "$TAG" "ath10k reload limit reached ($ath_reloads), fallback to reboot path"
        return 1
    fi
    ath_reloads=$((ath_reloads + 1))
    echo "$ath_reloads" > "$RELOAD_FILE"
    logger -t "$TAG" "ATH10K-RELOAD ($ath_reloads/$MAX_ATH10K_RELOADS): wifi wedged, reloading driver"
    modprobe -r ath10k_snoc 2>/dev/null
    sleep 2
    modprobe ath10k_snoc 2>/dev/null
    sleep 3
    # r7: 重载后 wlan0 不存在 = 探测失败 (error 90 深卡死), 等 5min 也不会好, 直接 reboot
    if ! ip link show wlan0 >/dev/null 2>&1; then
        logger -t "$TAG" "ATH10K-RELOAD failed (wlan0 gone, qmi stuck), rebooting now"
        sync
        sleep 2
        reboot
    fi
    # 重载后 NM 会自动重新关联 (autoconnect), 下轮 (5min) 验证
    return 0
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

# 成功: 两个计数器都清零 (r6: ath10k 重载计数在成功时也清零)
check_ok() {
    echo 0 > "$HARD_FAIL_FILE"
    echo 0 > "$SOFT_FAIL_FILE"
    echo 0 > "$RELOAD_FILE"
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
    # r6: 先判断是否驱动挂死 (扫描失败/dmesg crash) → 自愈重载
    #     连续 2 次软失败才触发, 避免开机 WiFi 还在关联时误杀
    if [ "$soft_failures" -ge 1 ]; then
        scan_ok=$(nmcli -t -f SSID dev wifi list 2>/dev/null | head -1)
        if [ -z "$scan_ok" ] || dmesg | tail -50 | grep -q "ath10k.*firmware crashed"; then
            if ath10k_selfheal; then
                exit 1
            fi
        fi
    fi
    soft_fail "wlan0 down (WiFi not associated, NM will retry)"
    exit 1
fi

# 4. ath10k 是否 crash (检查 dmesg 最近 100 行) - 硬故障
#    r6 调整: 关联成功时即使 dmesg 有 crash 记录也不算故障 (自恢复成功即可)
if ! ip addr show wlan0 2>/dev/null | grep -q "inet "; then
    if dmesg 2>/dev/null | tail -100 | grep -i "ath10k" | grep -iq "crash"; then
        hard_fail "ath10k firmware crash detected in dmesg"
        exit 1
    fi
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
