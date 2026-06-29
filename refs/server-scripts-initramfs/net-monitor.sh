#!/bin/sh
# net-monitor.sh (initramfs adapted)
# 频率: 5min
# 功能: 检查 wlan0/WiFi 连接/网关/外网/DNS, 统计 rx/tx
# 适配: 无 nmcli, 用 wpa_cli + ip

TAG="net-monitor"

# 1. wlan0 up?
if ! ip link show wlan0 2>/dev/null | grep -q "state UP"; then
    logger -t "$TAG" "CRITICAL wlan0 is down"
    exit 1
fi

# 2. WiFi connected? (wpa_cli instead of nmcli)
wpa_state=$(wpa_cli -i wlan0 status 2>/dev/null | awk -F= '/^wpa_state=/ {print $2}')
if [ "$wpa_state" != "COMPLETED" ]; then
    logger -t "$TAG" "WARN WiFi not connected: ${wpa_state:-unknown}"
fi

# 3. 网关连通性
gw=$(ip route 2>/dev/null | awk '/default/ {print $3; exit}')
gw_loss=100
if [ -n "$gw" ]; then
    ping_out=$(ping -c 5 -W 3 "$gw" 2>/dev/null)
    loss_str=$(echo "$ping_out" | awk -F'[, ]+' '/packet loss/ { for(i=1;i<=NF;i++) if($i ~ /%/){sub(/%/,"",$i); print $i; exit}}')
    gw_loss="${loss_str:-100}"
else
    logger -t "$TAG" "CRITICAL no default gateway (WiFi not connected?)"
fi

if [ "$gw_loss" -ge 50 ]; then
    logger -t "$TAG" "WARN gateway $gw loss=${gw_loss}%"
fi

# 4. 外网连通性
ext_loss=100
ping_out=$(ping -c 3 -W 3 8.8.8.8 2>/dev/null)
loss_str=$(echo "$ping_out" | awk -F'[, ]+' '/packet loss/ { for(i=1;i<=NF;i++) if($i ~ /%/){sub(/%/,"",$i); print $i; exit}}')
ext_loss="${loss_str:-100}"

# 5. DNS 解析
dns_ok=0
nslookup_out=$(nslookup baidu.com 2>/dev/null)
addr_lines=$(echo "$nslookup_out" | grep -ci "address")
if [ "$addr_lines" -ge 2 ]; then
    dns_ok=1
fi

if [ "$ext_loss" -ge 66 ] && [ "$dns_ok" -eq 0 ]; then
    logger -t "$TAG" "WARN external network down (loss=${ext_loss}%) and DNS failed"
fi

# 6. 网络统计
rx_bytes=$(awk '/wlan0:/ {print $2}' /proc/net/dev 2>/dev/null)
tx_bytes=$(awk '/wlan0:/ {print $10}' /proc/net/dev 2>/dev/null)
rx_mb=$(awk -v b="$rx_bytes" 'BEGIN { printf "%.2f", b/1048576 }')
tx_mb=$(awk -v b="$tx_bytes" 'BEGIN { printf "%.2f", b/1048576 }')

logger -t "$TAG" "wlan0: rx=${rx_mb}MB tx=${tx_mb}MB gw_loss=${gw_loss}% ext_loss=${ext_loss}% wpa=${wpa_state:-none}"
