# jason 设备状态清单 (Device State Manifest)

> 创建日期: 2026-06-28
> 用途: 记录 Xiaomi Mi Note 3 (jason) 当前刷入的 Linux 系统完整状态,作为可复现性的权威基准。
> 配套: [reproduce-from-scratch.sh](../scripts/reproduce-from-scratch.sh) (从零复现脚本) + [reflash-guide.md](./reflash-guide.md) (刷机流程)

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
| 当前内容 | pmOS boot.img (boot-nodebug.img) |
| kernel 版本 | `6.19.10-sdm660` (sdm660-mainline 社区 fork, tag v6.19.10-sdm660) |
| cmdline 特征 | **不含** `pmos.debug-shell` (正常自动启动) |
| cmdline 关键参数 | `console=ttyMSM0,115200 earlycon loglevel=8 pmos_boot_uuid=<UUID> pmos_root_uuid=<UUID>` |
| 镜像大小 | ~23 MB |
| 刷入方式 | `fastboot flash boot boot-nodebug.img` |
| 是否永久 | 是 (开机自动加载) |

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
| init 系统 | systemd (systemd-edge) |
| UI | console (无图形界面) |
| 架构 | aarch64 |
| 包管理 | apk (Alpine Linux) |
| 用户 | `user` (密码 `1234`, sudo 免密) |
| root 密码 | `1234` |

### 3.2 关键软件包

| 包 | 用途 |
|---|---|
| `device-xiaomi-jason` | jason 设备元信息 + initramfs 模块配置 |
| `linux-postmarketos-qcom-sdm660` | kernel 6.19.10-sdm660 (含 jason DTS + ath10k PS Mode patch + cpufreq-hw) |
| `firmware-xiaomi-jason` | WiFi board data (board.bin, 19152 字节, 从原厂 modem 分区提取) |
| `usb-network-jason` | **USB NCM 网络配置包** (固定接口名 usb0 + gadget 配置 + IP 监控) |
| `firmware-qcom-adreno-a530` | GPU zap shader (可选, 缺失静默降级) |
| `soc-qcom-sdm660` | SDM660 SoC 支持包 |
| `soc-qcom-sdm660-rproc` | modem/remoteproc 启用 (WiFi ath10k_snoc 依赖 modem 存活) |
| `NetworkManager` | 网络管理 (管理 wlan0) |
| `dnsmasq` | USB 网络 DHCP 服务器 |
| `openssh` | SSH 服务端 |
| `postmarketos-base` | pmOS 基础包 |

### 3.3 USB 网络配置 (usb-network-jason 包)

| 配置项 | 值 / 路径 |
|---|---|
| 接口名固定 | `usb0` (通过 `/etc/systemd/network/10-usb0.link` + udev 规则) |
| Gadget 配置 | NCM + ACM, `/usr/bin/setup-usb-gadget.sh` |
| 启动服务 | `setup-usb-gadget.service` (sysinit 阶段) |
| IP 监控服务 | `usb-ip-monitor.service` (multi-user 阶段, 持续重配) |
| NetworkManager 不管 usb0 | `/etc/NetworkManager/conf.d/99-usb0-unmanaged.conf` |
| udev 规则 | `/etc/udev/rules.d/99-usb-ncm.rules` |
| 详见 | [restart-plan.md §5](./restart-plan.md#5-方案-a-执行步骤-重新构建-rootfs) |

### 3.4 服务器优化 (已部署, 见 refs/server-scripts/)

- **P0 加固**: sysctl (`panic_on_oops=1`, `panic=120` 等) + journald 100M + eMMC fsck + SSH 加固 + health-check
- **P1 运维**: APK 更新通知 + 温度监控 (12 zones) + FakeRTC 持久化 + timesyncd (ntp.aliyun.com)
- **P2 监控**: 配置自动备份 (weekly) + 网络监控 + disk I/O 统计 + motd 系统状态
- 详见 [troubleshooting.md §7.8-7.10](./troubleshooting.md)

## 4. 网络

### 4.1 USB 网络 (NCM gadget)

| 项 | 值 |
|---|---|
| 接口名 | `usb0` (固定, 不被 udev 重命名为 enxXX) |
| 设备 IP | `172.16.42.1/24` |
| DHCP 范围 | `172.16.42.2` - `172.16.42.254` |
| 子网掩码 | `255.255.255.0` |
| 网关 | `172.16.42.1` (设备本身) |
| DNS | `172.16.42.1` (dnsmasq 转发) |
| DHCP 租约 | 12h |
| 主机连接方式 | USB 数据线, 主机通过 DHCP 获取 IP |

### 4.2 WiFi 网络

| 项 | 值 |
|---|---|
| 接口名 | `wlan0` |
| 驱动 | `ath10k_snoc` (WCN3990) |
| SSID | `ChinaNet-810` |
| 密码 | `WIFI_CHINANET_PASS_PLACEHOLDER` |
| IP (DHCP) | `192.168.1.12/24` |
| IPv6 | 双栈 (DHCPv6) |
| 信号强度 | 60-90 (扫描时) / 89 (连接后) |
| 链路速率 | 130 Mbps |
| NetworkManager 管理 | 是 (仅管 wlan0, 不管 usb0) |

## 5. SSH 访问

| 项 | 值 |
|---|---|
| 用户名 | `user` |
| 密码 | `1234` |
| 端口 | `22` |
| root 登录 | `PermitRootLogin no` (P0-6 加固) |
| MaxAuthTries | `3` (防爆破) |
| AllowUsers | `user` |
| **USB 通道** | `ssh user@172.16.42.1` |
| **WiFi 通道** | `ssh user@192.168.1.12` |
| 连接命令 | `sshpass -p 1234 ssh -o StrictHostKeyChecking=no user@<IP>` |

## 6. 关键 UUID (可复现性基准)

> 这两个 UUID 是 rootfs 子分区的标识,启动时通过 cmdline 传入 (`pmos_boot_uuid` / `pmos_root_uuid`)。
> 复现时必须保持一致,否则需同步更新 boot.img cmdline。

| 用途 | UUID |
|---|---|
| boot 子分区 (ext2) | `c5f7e8ec-1086-4198-beb1-5f9f7e21920c` |
| rootfs 子分区 (ext4) | `c79928f5-46b8-49de-8203-6124d458c7ce` |

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

执行 [reproduce-from-scratch.sh](../scripts/reproduce-from-scratch.sh) 后,验证以下条件全部满足:

- [ ] 设备开机自动进入 Linux (无需 `fastboot boot`)
- [ ] `uname -r` 输出包含 `6.19.10-sdm660`
- [ ] `dmesg | grep "firmware ver"` 显示 `1.0.0.591`
- [ ] `dmesg | grep "htt-ver"` 显示 `3.58`
- [ ] USB SSH 可达: `ssh user@172.16.42.1`
- [ ] WiFi 可扫描: `nmcli device wifi list`
- [ ] WiFi 可连接: `nmcli device wifi connect ChinaNet-810`
- [ ] WiFi 局域网 SSH 可达: `ssh user@192.168.1.12`
- [ ] `ip addr show usb0` 显示 `172.16.42.1/24`
- [ ] `ip addr show wlan0` 显示 `192.168.1.12/24` (连接后)
- [ ] boot 子分区 UUID = `c5f7e8ec-1086-4198-beb1-5f9f7e21920c`
- [ ] rootfs 子分区 UUID = `c79928f5-46b8-49de-8203-6124d458c7ce`
- [ ] systemd 全部服务启动: `systemctl --failed` 无失败项

## 9. 相关文档

- [reproduce-from-scratch.sh](../scripts/reproduce-from-scratch.sh) - 从零复现脚本
- [reflash-guide.md](./reflash-guide.md) - 刷机/回退/更新流程详解
- [restart-plan.md](./restart-plan.md) - 重做计划与背景
- [troubleshooting.md](./troubleshooting.md) - 故障排查 (含 WiFi firmware 修复 §7.4)
- [progress.md](./progress.md) - 工作进展记录
- [refs/jason-pmaports-patches/README.md](../refs/jason-pmaports-patches/README.md) - pmOS 包源改动说明
