#!/bin/sh
# restore-device-state.sh — 从 device-state-backup.tar.gz 一键恢复设备状态
# 用法: 在 Ubuntu 上执行 (设备需已通过 USB/WiFi SSH 可达)
#   ./restore-device-state.sh [备份包路径]
# 默认: backups/device-state-20260818/device-state-backup.tar.gz
# 恢复内容: /usr/local/bin 脚本 + systemd 单元 + NM/DNS 配置 + (可选)监控日志

set -e
BACKUP="${1:-backups/device-state-20260818/device-state-backup.tar.gz}"
PASS="${DEVICE_PASS:?需 ../secrets.env}"
SSH="sshpass -p $PASS ssh -o ConnectTimeout=8 -o PreferredAuthentications=password -o PubkeyAuthentication=no user@172.16.42.1"
SCP="sshpass -p $PASS scp -o PreferredAuthentications=password -o PubkeyAuthentication=no"

[ -f "$BACKUP" ] || { echo "备份包不存在: $BACKUP"; exit 1; }

echo "[1/5] 上传备份包..."
$SCP "$BACKUP" user@172.16.42.1:/tmp/restore.tar.gz

echo "[2/5] 解压暂存..."
$SSH 'echo $PASS | sudo -S sh -c "rm -rf /tmp/restore-stage && mkdir -p /tmp/restore-stage && tar -xzf /tmp/restore.tar.gz -C /tmp/restore-stage"'

echo "[3/5] 恢复脚本与单元..."
$SSH 'echo $PASS | sudo -S sh -c "
install -d /usr/local/bin /etc/systemd/system
cp -a /tmp/restore-stage/usr-local-bin/. /usr/local/bin/ 2>/dev/null || true
cp /tmp/restore-stage/systemd/*.service /tmp/restore-stage/systemd/*.timer /etc/systemd/system/ 2>/dev/null || true
chmod 755 /usr/local/bin/*
"'

echo "[4/5] 恢复配置..."
$SSH 'echo $PASS | sudo -S sh -c "
cp -a /tmp/restore-stage/etc/NetworkManager/. /etc/NetworkManager/ 2>/dev/null || true
cp /tmp/restore-stage/etc/resolv.conf /etc/ 2>/dev/null || true
cp -a /tmp/restore-stage/etc/journald.conf.d/. /etc/systemd/journald.conf.d/ 2>/dev/null || true
"'

echo "[5/5] 重载并启用 timers..."
$SSH 'echo $PASS | sudo -S sh -c "
systemctl daemon-reload
for t in battery-care temp-monitor net-monitor health-check disk-io-monitor fake-rtc-save apk-update config-backup fsck-check power-monitor discharge-monitor; do
  systemctl enable --now \$t.timer 2>/dev/null && echo \"  enabled \$t\" || true
done
systemctl list-timers --no-pager | head -15
rm -rf /tmp/restore-stage /tmp/restore.tar.gz
"'

echo "恢复完成. 验证: ssh user@172.16.42.1 systemctl list-timers"
