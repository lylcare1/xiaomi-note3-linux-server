# server-scripts

Xiaomi Mi Note 3 (jason) 移植为 Linux 服务器后的 H1/H2/H3 服务器优化脚本集。

本目录重建自 `docs/troubleshooting.md` §7.8-7.10 的描述（原设备 rootfs 被重刷覆盖后丢失）。目录结构对应设备根目录的部署路径，部署时按注释中的"对应设备 /xxx/yyy"路径拷贝即可。

## 目录结构

```
server-scripts/
├── usr-local-bin/           # 对应设备 /usr/local/bin/  (8 个监控脚本)
│   ├── health-check.sh
│   ├── temp-monitor.sh
│   ├── apk-update-check.sh
│   ├── fake-rtc-save.sh
│   ├── fake-rtc-restore.sh
│   ├── net-monitor.sh
│   ├── disk-io-monitor.sh
│   └── config-backup.sh
├── etc-profile.d/           # 对应设备 /etc/profile.d/  (登录 motd)
│   └── motd-status.sh
├── etc-sysctl.d/            # 对应设备 /etc/sysctl.d/   (内核参数)
│   └── 99-server-hardening.conf
├── etc-ssh-sshd_config.d/   # 对应设备 /etc/ssh/sshd_config.d/  (SSH 加固)
│   └── 99-server-hardening.conf
├── etc-systemd-journald.conf.d/  # 对应设备 /etc/systemd/journald.conf.d/
│   └── size.conf
├── etc-systemd/             # 对应设备 /etc/systemd/    (timesyncd)
│   └── timesyncd.conf
└── systemd/                 # 对应设备 /etc/systemd/system/  (17 个 unit)
    ├── health-check.service / .timer
    ├── temp-monitor.service / .timer
    ├── apk-update-check.service / .timer
    ├── fake-rtc-save.service / .timer
    ├── fake-rtc-restore.service        # 无 timer，开机时运行
    ├── net-monitor.service / .timer
    ├── disk-io-monitor.service / .timer
    ├── config-backup.service / .timer
    └── fsck-check.service / .timer
```

## 文件用途与来源

### 配置文件（按文档照抄）

| 文件 | 设备路径 | 来源章节 | 用途 |
|---|---|---|---|
| `etc-sysctl.d/99-server-hardening.conf` | `/etc/sysctl.d/` | §7.8.1 (P0-1) | 内核加固: panic_on_oops=1, panic=120, pid_max, swappiness 等 |
| `etc-systemd-journald.conf.d/size.conf` | `/etc/systemd/journald.conf.d/` | §7.8.2 (P0-2) | journald 日志上限 100M / 单文件 10M |
| `etc-ssh-sshd_config.d/99-server-hardening.conf` | `/etc/ssh/sshd_config.d/` | §7.8.4 (P0-4/6) | SSH 加固: MaxAuthTries=3, AllowUsers, 禁 root |
| `etc-systemd/timesyncd.conf` | `/etc/systemd/` | §7.9.4 (P1-4) | NTP 服务器: ntp.aliyun.com / cn.pool.ntp.org |

### Shell 脚本（按文档功能描述重建）

| 文件 | 设备路径 | 来源章节 | 用途 |
|---|---|---|---|
| `usr-local-bin/health-check.sh` | `/usr/local/bin/` | §7.8.5 (P0-5) | 健康检查 sshd/NM/wlan0/ath10k/网关, 连续 3 次失败自动 reboot |
| `usr-local-bin/temp-monitor.sh` | `/usr/local/bin/` | §7.9.2 (P1-2) | 扫描 12 个 thermal zone, CPU/GPU 70/85°C, 电池 55°C, PMIC 80°C |
| `usr-local-bin/apk-update-check.sh` | `/usr/local/bin/` | §7.9.1 (P1-1) | 检查 apk 更新, 安全包记 CRITICAL, 不自动升级 |
| `usr-local-bin/fake-rtc-save.sh` | `/usr/local/bin/` | §7.9.4 (P1-4) | 每 30min 写时间戳到 /var/lib/fake-rtc-time |
| `usr-local-bin/fake-rtc-restore.sh` | `/usr/local/bin/` | §7.9.4 (P1-4) | 开机时若 NTP 60s 内未同步则从文件恢复时间 |
| `usr-local-bin/net-monitor.sh` | `/usr/local/bin/` | §7.10.2 (P2-2) | 检查 wlan0/WiFi/网关/外网/DNS, 统计 rx/tx |
| `usr-local-bin/disk-io-monitor.sh` | `/usr/local/bin/` | §7.10.3 (P2-3) | 读 mmcblk1 (eMMC) I/O 统计, in_flight>50 WARN |
| `usr-local-bin/config-backup.sh` | `/usr/local/bin/` | §7.10.1 (P2-1) | 每周备份 25 个关键配置到 /var/backups, 保留 28 天 |
| `etc-profile.d/motd-status.sh` | `/etc/profile.d/` | §7.10.4 (P2-4) | 交互登录显示 uptime/load/mem/disk/temp/WiFi/警告 |

### systemd unit（对应设备 `/etc/systemd/system/`）

| Unit | 频率 | 来源 | 用途 |
|---|---|---|---|
| `health-check.timer` | 5min | P0-5 | 系统健康检查 + 自动 reboot |
| `temp-monitor.timer` | 5min | P1-2 | 温度监控告警 (12 zones) |
| `net-monitor.timer` | 5min | P2-2 | 网络监控告警 |
| `fake-rtc-save.timer` | 30min | P1-4 | 时间戳持久化 |
| `disk-io-monitor.timer` | 10min | P2-3 | eMMC I/O 统计 |
| `apk-update-check.timer` | 24h | P1-1 | APK 更新通知 |
| `fsck-check.timer` | 7d (周一 00:00) | P0-3 | eMMC 只读 fsck 检查 |
| `config-backup.timer` | 周一 03:00 | P2-1 | 配置文件备份 |
| `fake-rtc-restore.service` | 开机一次 | P1-4 | 恢复时间 (无 timer) |

## 部署步骤

1. **拷贝脚本到设备**（通过 SSH/USB 网络）：
   ```sh
   # usr-local-bin/* -> /usr/local/bin/
   scp usr-local-bin/*.sh user@172.16.42.1:/tmp/
   ssh user@172.16.42.1 'sudo mv /tmp/*.sh /usr/local/bin/ && sudo chmod +x /usr/local/bin/*.sh'

   # 配置文件
   ssh user@172.16.42.1 'sudo mkdir -p /etc/sysctl.d /etc/systemd/journald.conf.d /etc/ssh/sshd_config.d /etc/systemd /etc/profile.d'
   scp etc-sysctl.d/99-server-hardening.conf user@172.16.42.1:/tmp/
   # ... 依次拷贝
   ```

2. **应用配置**：
   ```sh
   sudo sysctl -p /etc/sysctl.d/99-server-hardening.conf
   sudo systemctl restart systemd-journald
   sudo systemctl reload sshd
   sudo systemctl restart systemd-timesyncd
   ```

3. **安装 systemd unit + 启用 timer**：
   ```sh
   sudo cp systemd/*.service systemd/*.timer /etc/systemd/system/
   sudo systemctl daemon-reload
   sudo systemctl enable --now health-check.timer temp-monitor.timer net-monitor.timer \
       disk-io-monitor.timer apk-update-check.timer fake-rtc-save.timer \
       fake-rtc-restore.service fsck-check.timer config-backup.timer
   ```

4. **一次性设置 eMMC fsck**（P0-3，非 service 一部分）：
   ```sh
   sudo tune2fs -c 30 -i 7d /dev/loop0p2
   ```

5. **验证**：
   ```sh
   systemctl list-timers --all          # 应看到 8 个 timer
   journalctl -t health-check -n 3      # 健康检查日志
   journalctl -t temp-monitor -n 3      # 温度日志
   journalctl -u fake-rtc-save -n 3     # FakeRTC 状态
   ```

## 完整 timer 体系（8 个）

| Timer | 频率 | 用途 | 来源 |
|---|---|---|---|
| `health-check.timer` | 5min | 系统健康检查 + 自动 reboot | P0-5 |
| `temp-monitor.timer` | 5min | 温度监控告警 (12 zones) | P1-2 |
| `net-monitor.timer` | 5min | 网络监控告警 | P2-2 |
| `fake-rtc-save.timer` | 30min | 时间戳持久化 | P1-4 |
| `disk-io-monitor.timer` | 10min | eMMC I/O 统计 | P2-3 |
| `apk-update-check.timer` | 24h | APK 更新通知 | P1-1 |
| `fsck-check.timer` | 7d (周一 00:00) | eMMC 只读 fsck 检查 | P0-3 |
| `config-backup.timer` | 周一 03:00 | 配置文件备份 | P2-1 |

## 兼容性说明

- 所有 shell 脚本使用 `#!/bin/sh`（POSIX sh），兼容 Alpine busybox ash
- 浮点比较/计算用 `awk`（busybox awk 可用），避免 bash 算术
- `ping -c N -W timeout` 兼容 busybox/iputils
- `nmcli`、`journalctl`、`systemctl` 为 pmOS 默认安装
- 日志统一用 `logger -t <tag>` 写入 journal，可用 `journalctl -t <tag>` 查看
