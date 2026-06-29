# jason 设备状态清单 (Device State Manifest)

> 创建日期: 2026-06-28 | 更新日期: 2026-06-29 (v3 initramfs 模式)
> 用途: 记录 Xiaomi Mi Note 3 (jason) 当前刷入的 Linux 系统完整状态,作为可复现性的权威基准。
> 配套: [reflash-guide.md](./reflash-guide.md) (刷机流程) + [progress.md](./progress.md) (工作进展)

## 1. 设备信息

| 项 | 值 |
|---|---|
| 设备型号 | Xiaomi Mi Note 3 |
| 内部代号 | jason |
| SoC | Qualcomm Snapdragon 660 (SDM660) |
| 内存 | 6 GB |
| 存储 | 128 GB eMMC (mmcblk1) |
| 序列号 | `d1236a7b` |
| Bootloader 状态 | **unlocked** |
| Android 版本 (原厂) | 7.1 (MIUI V8.5.9.0.NCHCNED) |
| 当前系统 | postmarketOS edge (Linux 服务器) |

## 2. 当前分区状态

> 三大关键分区已永久刷入 pmOS 相关镜像,开机即进入 Linux (无需 `fastboot boot`)。

### 2.1 boot 分区

| 项 | 值 |
|---|---|
| 分区用途 | 内核 + initramfs + 设备树 |
| 当前内容 | jason-boot-initramfs.img (initramfs 模式, PID 1 = busybox ash) |
| kernel 版本 | `6.19.10-sdm660` (sdm660-mainline 社区 fork, tag v6.19.10-sdm660) |
| cmdline 特征 | **不含** `pmos.debug-shell` (正常自动启动) |
| cmdline 关键参数 | `console=tty0 console=ttyMSM0,115200 fbcon=nodefer net.ifnames=0 loglevel=8 earlycon pmos_boot_uuid=<UUID> pmos_root_uuid=<UUID>` |
| initramfs 特性 | stay-in-initramfs (不 switch_root 到 systemd, USB NCM 稳定) |
| 镜像大小 | ~23 MB |
| 刷入方式 | `fastboot flash boot /tmp/jason-boot-initramfs.img` |
| 是否永久 | 是 (开机自动加载) |
| 构建脚本 | `scripts/deploy.sh --build-only` |

### 2.2 userdata 分区

| 项 | 值 |
|---|---|
| 分区用途 | pmOS rootfs (含 boot + rootfs 两个子分区) |
| 当前内容 | xiaomi-jason.img (2 分区镜像) |
| 镜像大小 | ~1.4 GB |
| 刷入方式 | `fastboot flash userdata xiaomi-jason.img` |
| 是否永久 | 是 (开机自动挂载) |

**子分区结构** (设备启动时由 `losetup -Pf userdata` 创建):

| 子分区 | 文件系统 | 大小 | 用途 | UUID |
|---|---|---|---|---|
| boot subpartition | ext2 | ~64 MB | boot.img (kernel+initramfs+dtb) | `c5f7e8ec-1086-4198-beb1-5f9f7e21920c` |
| rootfs subpartition | ext4 | ~1.3 GB | 根文件系统 (/) | `c79928f5-46b8-49de-8203-6124d458c7ce` |

### 2.3 modem 分区

| 项 | 值 |
|---|---|
| 分区用途 | 基带 + WiFi firmware (NON-HLOS.bin) |
| 当前内容 | **whyred V12** NON-HLOS.bin (非 jason 原厂) |
| 来源 | whyred V12.0.3.0.PEICNXM fastboot 包 |
| WiFi firmware 版本 | `1.0.0.591` |
| htt-ver | `3.58` |
| wlanmdsp.mbn 版本 | `WLAN.HL.1.0.1.c2-00538-QCAHLSWMTPLZ-1.214870.1` |
| 刷入原因 | jason 原厂 wlanmdsp.mbn (1.0.0.533) 与 mainline ath10k_snoc 不兼容, 启动 ~350ms 后 crash `PC=b00c749c` |
| 镜像大小 | 110 MB |
| 刷入方式 | `fastboot flash modem /tmp/NON-HLOS-whyred.bin` |
| 是否永久 | 是 |
| 详见 | [troubleshooting.md §7.4](./troubleshooting.md#74-wifi-2026-06-28-修复完成) |

### 2.4 其他分区

| 分区 | 状态 | 说明 |
|---|---|---|
| system / cache / cust | jason 原厂 | 未刷 pmOS (不影响 Linux 启动) |
| recovery | jason 原厂 (TWRP 临时 boot) | TWRP 不写入分区, 用 `fastboot boot twrp.img` |
| modemst1 / modemst2 / fsg | jason 原厂 (备份) | 运行时分区, 原厂 fastboot 包未覆盖, 见 [reflash-guide.md §1.3](./reflash-guide.md#13-恢复-modem-运行时分区-modemst1modemst2fsgpersist) |
| persist | jason 原厂 (备份) | 同上 |
| splash / frp / sec / ssd / limits / ddr / logfs / toolsfv / sti / apdp / msadp / devinfo / oops / mdtp / logdump | jason 原厂 | 见 `backups/original-jason-20260627-114354/` |

## 3. rootfs 内容

### 3.1 基础系统

| 项 | 值 |
|---|---|
| 发行版 | postmarketOS (pmOS) edge |
| init 系统 | **busybox ash** (initramfs 模式, PID 1 = `/bin/busybox ash /init_2nd.sh`) |
| systemd | **未启动** (initramfs 模式下不启动 systemd, USB NCM 稳定) |
| UI | console (无图形界面) + tty1 交互式 shell |
| 架构 | aarch64 |
| 包管理 | apk (Alpine Linux) |
| 用户 | `user` (密码 `1234`, sudo 免密) - 仅 rootfs 内 |
| root 登录 | SSH 密钥认证 (ed25519, `~/.ssh/id_ed25519_jason.pub`) |
| rootfs 上下文 | 通过 `chroot /sysroot` 访问 (sshd, server-daemon, wpa_supplicant 等) |

### 3.2 关键软件包

| 包 | 用途 |
|---|---|
| `device-xiaomi-jason` | jason 设备元信息 + initramfs 模块配置 |
| `linux-postmarketos-qcom-sdm660` | kernel 6.19.10-sdm660 (含 jason DTS + ath10k PS Mode patch + cpufreq-hw) |
| `firmware-xiaomi-jason` | WiFi board data (board.bin, 19152 字节, 从原厂 modem 分区提取) |
| `usb-network-jason` | USB NCM 网络配置包 (initramfs 内由 setup_usb_network + unudhcpd 实现) |
| `soc-qcom-sdm660-rproc` | modem/remoteproc 启用 (WiFi ath10k_snoc 依赖 modem 存活) |
| `openssh` | SSH 服务端 (sshd.pam, 从 initramfs 通过 chroot /sysroot 启动) |
| `wpa_supplicant` | WiFi 认证 (wpa_supplicant + wpa_cli) |
| `busybox-extras` | udhcpc (DHCP 客户端), nc (调试 shell) |
| `rmtfs` + `tqftpserv` + `diag-router` | modem 支持服务 (防 modem diag 饥饿崩溃) |
| `postmarketos-base` | pmOS 基础包 |

### 3.3 USB 网络 (initramfs 模式)

> USB NCM 在 initramfs 阶段由 pmOS 原生 `setup_usb_network` + `unudhcpd` 提供, 稳定运行。
> 不依赖 systemd / NetworkManager / udev .link 文件。

| 配置项 | 值 / 路径 |
|---|---|
| 接口名 | `usb0` (initramfs 阶段固定, cmdline `net.ifnames=0` 防止 udev 重命名) |
| Gadget 配置 | NCM, 由 `setup_usb_network` 函数 (init_functions.sh) 配置 |
| DHCP 服务 | `unudhcpd` (busybox, initramfs 内置) |
| 启动方式 | init_2nd.sh 第 22 行 `setup_usb_network` + `start_unudhcpd` |
| PID 1 守护 | init_2nd.sh 最后 `while true; do sleep 300; done` 保持 initramfs 不退出 |

### 3.4 服务器监控 (initramfs 适配, 见 refs/server-scripts-initramfs/)

> 无 systemd timers, 改用 `server-daemon.sh` 单进程循环调度器 (8 个任务)。
> 从 init_2nd.sh 通过 `chroot /sysroot /usr/local/bin/server-daemon.sh &` 启动。

| 任务 | 频率 | 脚本 | 说明 |
|---|---|---|---|
| health-check | 5min | health-check.sh | 检查 sshd/wlan0/磁盘, 3 次失败 reboot |
| temp-monitor | 5min | temp-monitor.sh | 12 个 thermal zone, 70°C 警告 |
| net-monitor | 5min | net-monitor.sh | wlan0/WiFi/网关连通性 (wpa_cli 替代 nmcli) |
| disk-io-monitor | 10min | disk-io-monitor.sh | mmcblk1 读写统计 |
| fake-rtc-save | 30min | fake-rtc-save.sh | 时间戳持久化 (无 RTC 硬件) |
| apk-update-check | 24h | apk-update-check.sh | apk 更新检查, 安全包 CRITICAL |
| config-backup | 7d | config-backup.sh | tar.gz 25 个关键配置, 保留 28 天 |
| fsck-check | 7d | (内联) | e2fsck -f -n /dev/loop0p2 只读检查 |

其他服务:
- `syslogd`: chroot /sysroot 启动, 为 `logger` 命令提供 /dev/log
- `motd-status.sh`: /etc/profile.d/, SSH 登录时显示系统状态
- `wifi-start.sh`: 幂等 WiFi 启动 (wpa_supplicant + udhcpc, 固定 MAC)

## 4. 网络

### 4.1 USB 网络 (NCM gadget)

| 项 | 值 |
|---|---|
| 接口名 | `usb0` (initramfs 固定, `net.ifnames=0` 防重命名) |
| 设备 IP | `172.16.42.1/16` |
| 主机 IP | `172.16.42.2` (DHCP 分配) |
| DHCP 服务 | `unudhcpd` (initramfs 内置, 非 dnsmasq) |
| 子网掩码 | `255.255.0.0` |
| 网关 | `172.16.42.1` (设备本身) |
| DNS | `8.8.8.8` (init_2nd.sh 写入 /sysroot/etc/resolv.conf) |
| 主机连接方式 | USB 数据线, 主机通过 DHCP 获取 IP |
| 调试端口 | 2222 (nc shell, initramfs 上下文, 无需认证) |

### 4.2 WiFi 网络

| 项 | 值 |
|---|---|
| 接口名 | `wlan0` |
| 驱动 | `ath10k_snoc` (WCN3990) |
| MAC 地址 | `02:1a:73:6b:03:01` (固定, wifi-start.sh 设置, 防 ath10k 随机 MAC) |
| 认证 | `wpa_supplicant` (非 NetworkManager, initramfs 模式无 NM) |
| 配置文件 | `/etc/wpa_supplicant/wpa_supplicant.conf` (rootfs 持久化) |
| SSID | `ChinaNet-810` |
| 密码 | `WIFI_CHINANET_PASS_PLACEHOLDER` |
| IP (DHCP) | `192.168.1.17/24` (udhcpc 获取, 固定 MAC 后 DHCP 分配稳定) |
| IPv6 | 双栈 (SLAAC, `240e:370:...`) |
| 网关 | `192.168.1.1` |
| DNS | `192.168.1.1` (DHCP 下发) |
| 自动启动 | init_2nd.sh WiFi starter 子 shell (boot 后 ~47s 完成) |
| 启动脚本 | `/usr/local/bin/wifi-start.sh` (幂等, 不杀工作进程) |

## 5. SSH 访问

> initramfs 模式下 sshd 从 init_2nd.sh 通过 `chroot /sysroot /usr/sbin/sshd.pam` 启动。
> SSH 会话在 rootfs (chroot) 上下文中运行。

| 项 | 值 |
|---|---|
| 用户名 | `root` (密钥认证) |
| 认证方式 | **ed25519 公钥** (`~/.ssh/id_ed25519_jason`, 主机端) |
| 密码认证 | 默认禁用 (root 密码锁定 `!`) |
| 端口 | `22` |
| sshd 进程名 | `sshd.pam` (非 `sshd`, pgrep 需用 `pgrep -f sshd`) |
| 主机 SSH 配置 | `~/.ssh/config.d/jason.conf` (别名 `jason` / `jason-wifi`) |
| **USB 通道** | `ssh jason` (= `ssh root@172.16.42.1`) |
| **WiFi 通道** | `ssh jason-wifi` (= `ssh root@192.168.1.17`) |
| **nc 调试** | `nc 172.16.42.1 2222` (initramfs 上下文, 无需认证, port 2222) |

## 6. 关键 UUID (可复现性基准)

> 这两个 UUID 是 rootfs 子分区的标识,启动时通过 cmdline 传入 (`pmos_boot_uuid` / `pmos_root_uuid`)。
> 复现时必须保持一致,否则需同步更新 boot.img cmdline。

| 用途 | UUID |
|---|---|
| boot 子分区 (ext2) | `c3111c1f-5df3-4143-8005-7bc8abcb12c0` |
| rootfs 子分区 (ext4) | `55b176e9-7dba-4871-87cb-68314c590292` |

## 7. 回退路径

> 任何时候都可回退到原厂 Android 系统,所有备份完整可用。

### 7.1 一键回退到原厂 Android

```bash
cd jason_images_V8.5.9.0.NCHCNED_20170831.0000.00_7.1_cn
./flash_all.sh
# 然后进 TWRP 恢复 modemst1/modemst2/fsg/persist (见 reflash-guide.md §1.3)
```

### 7.2 备份清单

| 备份项 | 路径 | 大小 | 说明 |
|---|---|---|---|
| 原厂 fastboot 包 | `jason_images_V8.5.9.0.NCHCNED_20170831.0000.00_7.1_cn/` | 2.0 GB | 完整原厂镜像 |
| 28 分区备份 | `backups/original-jason-20260627-114354/` | 6.7 GB | 含 13 个核心分区 sha256 校验 |
| jason 原厂 NON-HLOS.bin | `backups/original-jason-20260627-114354/modem.img` | 192 MB | 原厂 WiFi firmware (1.0.0.533, 不兼容 mainline) |
| modemst1/modemst2/fsg/persist | `backups/original-jason-20260627-114354/` | - | 运行时分区 (原厂包未覆盖) |

### 7.3 仅回退 boot 分区 (保留 pmOS rootfs)

```bash
fastboot flash boot backups/original-jason-20260627-114354/boot.img
```

详见 [reflash-guide.md §1](./reflash-guide.md#1-完整刷回原厂-jason--android) 和 [§6](./reflash-guide.md#6-故障恢复)。

## 8. 复现性验证清单

> initramfs 模式验证清单 (无 systemd, 无 nmcli, 无 systemctl)

- [ ] 设备开机自动进入 Linux (无需 `fastboot boot`)
- [ ] `uname -r` 输出包含 `6.19.10-sdm660`
- [ ] PID 1 是 busybox ash: `ps -p 1 -o comm=` 输出 `ash` (非 systemd)
- [ ] USB SSH 可达: `ssh jason` (密钥认证)
- [ ] `dmesg | grep "firmware ver"` 显示 `1.0.0.591`
- [ ] `dmesg | grep "htt-ver"` 显示 `3.58`
- [ ] WiFi 自动连接: boot 后 60s `ip addr show wlan0` 显示 `192.168.1.17/24`
- [ ] WiFi 局域网 SSH 可达: `ssh jason-wifi`
- [ ] `ip addr show usb0` 显示 `172.16.42.1/16`
- [ ] wpa_supplicant 运行: `pgrep -f "wpa_supplicant.*wlan0"`
- [ ] udhcpc 运行: `pgrep -f "udhcpc.*wlan0"`
- [ ] server-daemon 运行: `pgrep -f server-daemon`
- [ ] modem 稳定: `cat /sys/class/remoteproc/remoteproc2/state` = `running`
- [ ] ADSP 稳定: `cat /sys/class/remoteproc/remoteproc0/state` = `running`
- [ ] WiFi MAC 固定: `ip link show wlan0 | grep link` 包含 `02:1a:73:6b:03:01`
- [ ] boot 子分区 UUID = `c3111c1f-5df3-4143-8005-7bc8abcb12c0`
- [ ] rootfs 子分区 UUID = `55b176e9-7dba-4871-87cb-68314c590292`

## 9. 相关文档

- [reflash-guide.md](./reflash-guide.md) - 刷机/回退/更新流程详解
- [troubleshooting.md](./troubleshooting.md) - 故障排查 (含 WiFi firmware 修复 §7.4)
- [progress.md](./progress.md) - 工作进展记录 (含 v3 6 阶段计划)
- [refs/jason-pmaports-patches/README.md](../refs/jason-pmaports-patches/README.md) - pmOS 包源改动说明
- [scripts/deploy.sh](../scripts/deploy.sh) - 构建/刷入/验证一体化脚本
- [scripts/stability-test.sh](../scripts/stability-test.sh) - 30 分钟稳定性测试
- 归档文档: [docs/archive/](./archive/) (v1/v2 计划, 首阶段 checklist, 模板等)
