#!/bin/bash
# F1. 长稳运行测试
# 用法: ./scripts/long-stability-test.sh [持续时间秒数, 默认 3600=1h]
# 输出: logs/stability-<timestamp>.log

DURATION=${1:-3600}
DEVICE_IP=192.168.1.12
DEVICE_USER=user
DEVICE_PASS=1234
INTERVAL=60  # 每次采样间隔(秒)
LOGDIR="/home/lyl/Documents/system/XiaoMiNote3/logs"
mkdir -p "$LOGDIR"
TS=$(date +%Y%m%d-%H%M%S)
LOG="$LOGDIR/stability-$TS.log"

echo "=== 长稳测试启动 $(date) ===" | tee "$LOG"
echo "目标: $DEVICE_USER@$DEVICE_IP, 持续 ${DURATION}s, 间隔 ${INTERVAL}s" | tee -a "$LOG"
echo "日志: $LOG" | tee -a "$LOG"
echo "" | tee -a "$LOG"

START=$(date +%s)
END=$((START + DURATION))
ITER=0

while [ $(date +%s) -lt $END ]; do
    ITER=$((ITER + 1))
    NOW=$(date +%H:%M:%S)

    # 主机端 ping 测试
    PING_RESULT=$(ping -c 3 -W 2 $DEVICE_IP 2>&1)
    PING_LOSS=$(echo "$PING_RESULT" | grep -oE '[0-9]+% packet loss' | head -1)
    PING_RTT=$(echo "$PING_RESULT" | grep -oE 'rtt min/avg/max/mdev = [0-9.]+/[0-9.]+/[0-9.]+/[0-9.]+' | head -1)

    # 设备端采集 (uptime/load/mem/thermal/wifi)
    DEV_STATS=$(sshpass -p 1234 ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 $DEVICE_USER@$DEVICE_IP "
        UP=\$(cut -d' ' -f1 /proc/uptime)
        LOAD=\$(cat /proc/loadavg | cut -d' ' -f1-3)
        MEM=\$(free -m | awk '/^Mem:/ {print \$3\"/\"\$2\"M\"}')
        WLAN_IP=\$(ip -4 addr show wlan0 2>/dev/null | awk '/inet / {print \$2}' | head -1)
        WLAN_STATE=\$(cat /sys/class/net/wlan0/operstate 2>/dev/null)
        CPU_THERMAL=\$(cat /sys/class/thermal/thermal_zone3/temp 2>/dev/null)
        GPU_THERMAL=\$(cat /sys/class/thermal/thermal_zone8/temp 2>/dev/null)
        BATT_THERMAL=\$(cat /sys/class/thermal/thermal_zone9/temp 2>/dev/null)
        echo \"up=\${UP}s load=\${LOAD} mem=\${MEM} wlan_state=\${WLAN_STATE} wlan_ip=\${WLAN_IP} cpu_t=\${CPU_THERMAL} gpu_t=\${GPU_THERMAL} batt_t=\${BATT_THERMAL}\"
    " 2>/dev/null)

    if [ -z "$DEV_STATS" ]; then
        DEV_STATS="SSH_FAIL"
    fi

    printf "[%s] iter=%d  ping=%s  %s  rtt=%s\n" "$NOW" "$ITER" "$PING_LOSS" "$DEV_STATS" "$PING_RTT" | tee -a "$LOG"

    # 检测异常
    if echo "$PING_LOSS" | grep -q '^100%'; then
        echo "[$NOW] ALERT: 100% packet loss at iter $ITER" | tee -a "$LOG"
    fi
    if echo "$DEV_STATS" | grep -q 'SSH_FAIL'; then
        echo "[$NOW] ALERT: SSH connection failed at iter $ITER" | tee -a "$LOG"
    fi
    if echo "$DEV_STATS" | grep -q 'wlan_state=down\|wlan_state='; then
        :
    fi
    # 检测 ath10k crash
    CRASH=$(sshpass -p 1234 ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 $DEVICE_USER@$DEVICE_IP "echo 1234 | sudo -S dmesg 2>/dev/null | grep -cE 'ath10k.*fatal error|wlan_process.*crash|watchdog timer expired'" 2>/dev/null)
    if [ -n "$CRASH" ] && [ "$CRASH" -gt 0 ]; then
        echo "[$NOW] ALERT: ath10k crash detected! count=$CRASH" | tee -a "$LOG"
    fi

    sleep $INTERVAL
done

echo "" | tee -a "$LOG"
echo "=== 长稳测试结束 $(date) ===" | tee -a "$LOG"
ITER_TOTAL=$ITER
echo "总采样次数: $ITER_TOTAL" | tee -a "$LOG"
echo "日志保存在: $LOG"
