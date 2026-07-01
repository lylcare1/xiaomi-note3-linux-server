# Xiaomi Mi Note 3 (jason) Linux 服务器使用文档

> 废旧手机改造的无头 Linux 服务器，开机即用，零成本、低功耗。

## 1. 设备概述

| 项目 | 值 |
|------|-----|
| 设备 | Xiaomi Mi Note 3 (codename: jason) |
| SoC | Qualcomm SDM660 (8 核: 4×A53@1.84GHz + 4×A73@2.46GHz) |
| 内存 | 4 GB |
| 存储 | 64 GB eMMC (rootfs 占 49.3G) |
| 系统 | postmarketOS (Alpine Linux) |
| 内核 | 6.19.10-sdm660 (r31, 含 cpufreq 补丁) |
| 功耗 | ~2W (空闲) |
| Bootloader | 已解锁 |

## 2. 连接方式

### USB NCM（首选，开机即用）

用数据线连接手机与电脑，开机后自动枚举 USB NCM 网卡。

```bash
ssh user@172.16.42.1        # 密码: 1234
```

- IP: `172.16.42.1/16`
- 用户: `user` (密码 `1234`)
- root: `sudo -S` (用 user 密码)

### WiFi（局域网）

开机后 NetworkManager 自动连接已保存的 WiFi。

```bash
ssh user@192.168.66.165     # 当前 IP (DHCP 分配)
```

- SSID: `Green Tree Inn` (当前)
- IP 由 DHCP 分配，可能变化
- 查看当前 IP: `ssh user@172.16.42.1 'ip -4 addr show wlan0'`

### 添加新 WiFi

```bash
ssh user@172.16.42.1
sudo nmcli device wifi connect "<SSID>" password "<PASSWORD>" ifname wlan0
# 连接会自动保存，开机自动连接
```

## 3. 系统信息

### CPU / cpufreq

```bash
nproc                                    # 8
cat /proc/cpuinfo | grep processor       # cpu0-cpu7
# cpufreq (schedutil governor, 自动调频)
cat /sys/devices/system/cpu/cpufreq/policy0/scaling_cur_freq   # 小核
cat /sys/devices/system/cpu/cpufreq/policy1/scaling_cur_freq   # 大核
# 频率范围
# policy0 (cpu0-3): 633600 - 1843200 kHz
# policy1 (cpu4-7): 1113600 - 2457600 kHz
```

### 温度

```bash
cat /sys/class/thermal/thermal_zone*/temp
# 空闲: 40-43°C  高负载: 60-70°C  保护阈值: 85°C
```

### 内存 / 磁盘

```bash
free -m                    # 3624M total
df -h /                    # /dev/loop0p2 49.3G
lsblk                      # mmcblk1p70 (userdata) → loop0p1 (boot) + loop0p2 (root)
```

### 服务状态

```bash
systemctl is-active sshd NetworkManager
systemctl list-timers --all
```

## 4. 常用运维操作

### 重启 / 关机

```bash
sudo reboot
sudo poweroff
```

### 切换到 fastboot（维护用）

```bash
sudo reboot bootloader
# 或关机后按住 Vol- + Power
```

### 查看内核日志

```bash
dmesg | tail -50
journalctl -u sshd -n 50
```

### 软件包管理（apk）

```bash
sudo apk update
sudo apk add <package>
sudo apk upgrade
```

### WiFi 管理

```bash
nmcli device wifi list                    # 扫描
nmcli conn                                # 已保存连接
nmcli conn delete "<SSID>"                # 删除连接
nmcli device wifi connect "<SSID>" password "<PWD>" ifname wlan0
```

## 5. 部署 / 重刷流程

### 一键部署（主机侧）

部署脚本: [scripts/deploy.sh](../scripts/deploy.sh)

```bash
# 完整部署 (设备需在 fastboot)
./scripts/deploy.sh --all              # update-uuid + flash-rootfs + boot-temp + verify

# 持久化 boot 分区 (设备需已启动且 SSH 可达)
./scripts/deploy.sh --persist          # flash-boot (dd) + verify

# 单独步骤
./scripts/deploy.sh --update-uuid      # 从 rootfs 镜像更新 boot.img UUID
./scripts/deploy.sh --flash-rootfs     # fastboot flash userdata
./scripts/deploy.sh --boot-temp        # fastboot boot (临时)
./scripts/deploy.sh --flash-boot       # dd 写入 boot 分区 (持久化)
./scripts/deploy.sh --verify           # 验证 SSH + cpufreq
```

### 更新内核流程

1. 在 pmaports 中修改内核补丁
2. `pmbootstrap build linux-xiaomi-jason`
3. `pmbootstrap install`
4. `pmbootstrap export`
5. `./scripts/deploy.sh --all` (设备进 fastboot)
6. `./scripts/deploy.sh --persist` (设备启动后持久化)

### 刷回原厂

详见 [docs/reflash-guide.md](./reflash-guide.md)。原厂包在 `jason_images_V8.5.9.0.NCHCNED_20170831.0000.00_7.1_cn/`。

## 6. 启动流程

```
按电源键
  → bootloader 从 boot 分区加载 r31 内核
    → 内核启动 (cmdline: net.ifnames=0 cpuidle.off=1 consoleblank=60)
      → initramfs (USB NCM 网卡枚举 + losetup userdata)
        → switch_root → rootfs systemd
          → sshd + NetworkManager + WiFi 自动连接
            → SSH 可用 (约 60-90s)
```

无需任何手动干预，开机即 Linux。

## 7. 性能参考

对比 2 核 Intel Xeon Platinum 云服务器 (116.62.69.18):

| 测试 | Xiaomi Note 3 | x86 服务器 | 比值 |
|------|--------------|-----------|------|
| CPU 单核 md5 | 83 MB/s | 421 MB/s | 1/5 |
| CPU 多核总吞吐 | 400 MB/s | 605 MB/s | 2/3 |
| 内存带宽 | 1.5 GB/s | 6.7 GB/s | 1/4.5 |
| 磁盘写 | 401 MB/s | 612 MB/s | 2/3 |
| 网络延迟 (8.8.8.8) | 201ms | 193ms | 相当 |

**适用场景**: 轻量常驻服务（SSH 跳板、监控、MQTT、轻量 Web、cron），低并发，功耗敏感。
**不适用**: CPU 密集计算、高并发数据库、内存带宽敏感应用。

## 8. 注意事项

- **boot 分区持久化**: 用 `dd` 写入 (非 `fastboot flash boot`)，详见 [scripts/deploy.sh](../scripts/deploy.sh) `--flash-boot`
- **UUID 同步**: 每次 `pmbootstrap install` 后 rootfs UUID 会变，必须用 `--update-uuid` 更新 boot.img cmdline
- **cpuidle.off=1**: 内核 cmdline 参数，禁用 cpuidle 避免已知死锁
- **WiFi firmware**: 设备 modem 分区刷入 whyred NON-HLOS.bin (fw 1.0.0.591)，详见 [docs/troubleshooting.md](./troubleshooting.md) §7.4
- **回退路径**: 原厂备份在 `backups/original-jason-20260627-114354/`，原厂 fastboot 包可随时刷回
- **温度**: 空闲 40-43°C，长期高负载建议外接散热

## 9. 关键文件索引

| 文件 | 用途 |
|------|------|
| [scripts/deploy.sh](../scripts/deploy.sh) | 一键部署脚本 |
| [scripts/modify-bootimg-cmdline.py](../scripts/modify-bootimg-cmdline.py) | boot.img cmdline 修改工具 |
| [docs/progress.md](./progress.md) | 完整工作进展记录 |
| [docs/reflash-guide.md](./reflash-guide.md) | 刷机/回退流程 |
| [docs/troubleshooting.md](./troubleshooting.md) | 故障排查 |
| [docs/device-state-manifest.md](./device-state-manifest.md) | 设备状态清单 |
| backups/original-jason-* | 原厂分区备份 |
| jason_images_V8.5.9.0* | 原厂 fastboot 包 |
