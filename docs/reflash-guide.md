# jason 刷回 / 重刷 / 更新流程

> 创建日期: 2026-06-28
> 用途: jason 设备 (Xiaomi Mi Note 3) 的所有刷机/回退/更新操作流程
> 配套: [troubleshooting.md](./troubleshooting.md) §7.4-7.5 (WiFi firmware 修复)

## 0. 前置准备

### 0.1 必要文件清单

| 用途 | 路径/来源 | 大小 |
|---|---|---|
| 原厂 fastboot 包 (回退用) | `jason_images_V8.5.9.0.NCHCNED_20170831.0000.00_7.1_cn/` | 2.0 GB |
| pmOS rootfs 镜像 (含 boot+rootfs 2 分区) | `xiaomi-jason.img` | 1.4 GB |
| pmOS kernel boot 镜像 (单独) | `boot-no-debug.img` | 23 MB |
| **whyred V12 NON-HLOS.bin (WiFi 修复)** | `/tmp/NON-HLOS-whyred.bin` | 110 MB |
| TWRP 镜像 (临时 boot 用) | `twrp-3.7.0_9-0-jason.img` | 64 MB |
| 原厂分区备份 (28 个) | `backups/original-jason-20260627-114354/` | 6.7 GB |
| jason 原厂 NON-HLOS.bin (备份) | `backups/original-jason-20260627-114354/modem.img` | 192 MB |

### 0.2 设备状态确认

```bash
# 设备序列号
fastboot devices
# 期望: d1236a7b  fastboot

# 设备 unlock 状态
echo HOST_SUDO_PASS_PLACEHOLDER | sudo -S fastboot oem device-info 2>&1 | grep -i unlocked
# 期望: Device unlocked: true
```

### 0.3 sudo 别名 (本机)

```bash
# 本地电脑密码 HOST_SUDO_PASS_PLACEHOLDER, 所有 fastboot/adb 命令均需 sudo
alias fb='echo HOST_SUDO_PASS_PLACEHOLDER | sudo -S fastboot'
alias ad='echo HOST_SUDO_PASS_PLACEHOLDER | sudo -S adb'
```

---

## 1. 完整刷回原厂 (jason → Android)

> 适用: 想彻底还原到出厂 Android 状态

### 1.1 进入 fastboot

```bash
# 设备开机状态下:
adb reboot bootloader

# 设备关机状态下: 按住 音量下 + 电源

# 确认设备已就绪
fb devices
```

### 1.2 刷原厂分区 (按 fastboot 包内顺序)

```bash
cd jason_images_V8.5.9.0.NCHCNED_20170831.0000.00_7.1_cn

# 方式 A: 用官方脚本 (推荐)
./flash_all.sh

# 方式 B: 手动逐分区刷 (如果你想保留某些数据)
fb flash boot boot.img
fb flash system system.img
fb flash cache cache.img
fb flash cust cust.img
fb flash recovery recovery.img
fb flash modem NON-HLOS.bin
fb flash dsp dsp.bin
fb flash bluetooth BTFM.bin
fb flash misc misc.img
fb flash splash splash.img
fb flash frp frp.img
fb flash sec sec.dat
fb flash ssd ssd.bin
fb flash limits limits.mbn
fb flash ddr DDR_UMS.bin
fb flash logfs logfs.bin
fb flash toolsfv toolsfv.mbn
fb flash sti sti.mbn
fb flash apdp apdp.mbn
fb flash msadp msadp.mbn
fb flash devinfo devinfo.mbn
fb flash oops oops.mbn
fb flash mdtp mdtp.img
fb flash logdump logdump.img

# userdata 可选擦除
fb erase userdata
fb erase cache

fb reboot
```

### 1.3 恢复 modem 运行时分区 (modemst1/modemst2/fsg/persist)

> 原厂 fastboot 包**不包含**这 4 个分区,必须从备份恢复,否则 WiFi/基带会异常

```bash
# 进 TWRP (临时 boot,不刷到分区)
fb boot twrp-3.7.0_9-0-jason.img
sleep 30

# 推送 + dd 写回
cd /home/lyl/Documents/system/XiaoMiNote3
ad push backups/original-jason-20260627-114354/modemst1.img /sdcard/
ad push backups/original-jason-20260627-114354/modemst2.img /sdcard/
ad push backups/original-jason-20260627-114354/fsg.img /sdcard/
ad push backups/original-jason-20260627-114354/persist.img /sdcard/

ad shell dd if=/sdcard/modemst1.img of=/dev/block/bootdevice/by-name/modemst1 bs=4194304
ad shell dd if=/sdcard/modemst2.img of=/dev/block/bootdevice/by-name/modemst2 bs=4194304
ad shell dd if=/sdcard/fsg.img      of=/dev/block/bootdevice/by-name/fsg      bs=4194304
ad shell dd if=/sdcard/persist.img  of=/dev/block/bootdevice/by-name/persist  bs=4194304

ad reboot
```

### 1.4 验证

设备重启后应该进入 Android 原厂系统。若卡 mi Logo,大概率是 modemst1/modemst2/fsg 未恢复。

---

## 2. 重刷 pmOS (Android → Linux)

> 适用: 设备已是 Android,想重新部署 pmOS Linux

### 2.1 进入 fastboot

```bash
adb reboot bootloader  # 或关机后 音量下 + 电源
fb devices
```

### 2.2 刷 pmOS rootfs (含 boot+rootfs)

```bash
# rootfs 镜像 xiaomi-jason.img 包含 2 个分区 (boot + rootfs)
# 写入 userdata 分区 (会覆盖整个 userdata,52GB)
fb flash userdata xiaomi-jason.img

# 验证 (可选,查看分区表)
fb getvar partition-type:userdata
```

### 2.3 **必刷: WiFi firmware 修复 (whyred NON-HLOS.bin)**

> 跳过此步会导致 WiFi firmware 启动后立即 crash (PC=b00c749c)
> 详见 [troubleshooting.md §7.4](./troubleshooting.md#74-wifi-2026-06-28-修复完成)

```bash
# 刷入 whyred V12 完整 NON-HLOS.bin 到 modem 分区
# 注意: jason 原厂 NON-HLOS.bin 是 143MB, whyred 的是 110MB
#       用 whyred 的覆盖,modem 分区足够大
fb flash modem /tmp/NON-HLOS-whyred.bin
```

**whyred NON-HLOS.bin 来源**:
```bash
# 下载 whyred V12.0.3.0.PEICNXM fastboot 包 (2.5GB)
wget https://bn.d.miui.com/V12.0.3.0.PEICNXM/whyred_images_V12.0.3.0.PEICNXM_20210509.0000.00_9.0_cn_59bb23dffc.tgz

# 解压提取 NON-HLOS.bin
tar xzf whyred_images_V12.0.3.0.PEICNXM_*.tgz
find whyred_images_V12.0.3.0.PEICNXM_* -name 'NON-HLOS.bin' -exec cp {} /tmp/NON-HLOS-whyred.bin \;
```

### 2.4 冷启动 pmOS

```bash
# 不要用 fb reboot, 要用 fb boot 直接启动 kernel 镜像 (确保是冷启动)
# QMI 协商需要冷启动, warm reboot 会导致 modem 状态不一致
fb boot boot-no-debug.img

# 等 60 秒系统启动完成
sleep 60
```

### 2.5 验证启动

```bash
# 通过 USB 网络 (172.16.42.1) 或 WiFi 局域网连接
sshpass -p 1234 ssh -o StrictHostKeyChecking=no user@172.16.42.1 "uname -a"
# 期望: Linux xiaomi-jason 6.19.10-sdm660 ...

# 检查 WiFi firmware 版本
sshpass -p 1234 ssh user@172.16.42.1 "dmesg | grep -E 'firmware ver|htt-ver'"
# 期望: firmware ver 1.0.0.591, htt-ver 3.58

# 检查 wlan0 接口
sshpass -p 1234 ssh user@172.16.42.1 "ip addr show wlan0"
# 期望: state UP, inet <assigned-ip>
```

---

## 3. 仅更新内核 (boot.img)

> 适用: rootfs 不变, 只想换内核 (例如调试新 patch)

### 3.1 方法 A: fastboot boot 临时测试 (推荐, 不刷分区)

```bash
fb boot boot-new-test.img
```

### 3.2 方法 B: 刷入 boot 分区 (持久)

> 注意: jason 的 pmOS rootfs 使用 userdata 分区中的 boot subpartition
> 直接刷 boot 分区**不会**影响 pmOS 启动 (pmOS 从 userdata 加载 boot)

```bash
fb flash boot boot-new.img
```

### 3.3 方法 C: 更新 rootfs 中的 boot 子分区 (持久, pmOS 启动用)

```bash
# 1. 通过 SSH 推送新的 boot.img 到设备
sshpass -p 1234 scp boot-new.img user@172.16.42.1:/tmp/

# 2. 设备上 dd 写入 boot subpartition
sshpass -p 1234 ssh user@172.16.42.1 "
echo 1234 | sudo -S dd if=/tmp/boot-new.img of=/dev/loop0p1 bs=4M
echo 1234 | sudo -S sync
"
# 注意: /dev/loop0p1 是 rootfs 镜像中的 boot 分区, 设备启动时由 losetup -Pf userdata 创建

# 3. 重启
sshpass -p 1234 ssh user@172.16.42.1 "echo 1234 | sudo -S reboot"
```

---

## 4. 更新 WiFi firmware

> 适用: 想换不同版本的 wlanmdsp.mbn / NON-HLOS.bin

### 4.1 完整 NON-HLOS.bin 替换 (推荐)

```bash
# 进入 fastboot
adb reboot bootloader

# 刷入新的 NON-HLOS.bin
fb flash modem /path/to/new-NON-HLOS.bin

# 冷启动
fb boot boot-no-debug.img
```

### 4.2 仅替换 wlanmdsp.mbn (不推荐)

> **警告**: wlanmdsp.mbn 与 NON-HLOS.bin 中其他固件组件 (mba.mbn, modem.b*, adsp.b*, cdsp.b*) 版本强耦合
> 只替换 wlanmdsp.mbn 会导致 modem watchdog timeout
> 详见 [troubleshooting.md §7.4.6](./troubleshooting.md#746-已排除方案)

如必须尝试,需用 FAT 工具解包 NON-HLOS.bin,替换 wlanmdsp.mbn,重新打包:

```bash
# 安装 fatsort 或 fatcat
sudo apt install fatcat

# 解包
fatcat -x /tmp/non-hlos-extracted /tmp/NON-HLOS.bin

# 替换 wlanmdsp.mbn
cp /tmp/wlanmdsp-new.mbn /tmp/non-hlos-extracted/wlanmdsp.mbn

# 重新打包 (复杂,需保持 FAT 文件系统结构,不推荐)
# 推荐用 mkfs.fat + cp + fatcat 重打包,或直接用 whyred 完整 NON-HLOS.bin
```

---

## 5. 更新 rootfs (重新 pmbootstrap install)

> 适用: 想升级 pmOS 用户态 (添加/删除包, 修改配置等)

### 5.1 在本机重新生成 rootfs

```bash
cd /home/lyl/.local/var/pmbootstrap/cache_git/pmaports

# 修改 device-xiaomi-jason/APKBUILD 或其他文件后
pmbootstrap install

# 生成的镜像在
ls -lh /home/lyl/.local/var/pmbootstrap/chroot_native/home/pmos/rootfs/
# xiaomi-jason.img
```

### 5.2 刷入新 rootfs (会丢失设备上的数据!)

```bash
adb reboot bootloader

# 刷入新 rootfs (覆盖整个 userdata)
fb flash userdata /home/lyl/.local/var/pmbootstrap/chroot_native/home/pmos/rootfs/xiaomi-jason.img

# 重刷 WiFi firmware (新 rootfs 不影响 modem 分区,但保险起见可再刷一次)
# fb flash modem /tmp/NON-HLOS-whyred.bin   # 已刷过则跳过

# 冷启动
fb boot boot-no-debug.img
```

### 5.3 WiFi 连接配置 (新 rootfs 需重新配置)

```bash
# 通过 USB 网络连接
sshpass -p 1234 ssh user@172.16.42.1

# 扫描并连接 WiFi
sudo nmcli device wifi connect 'ChinaNet-810' password 'WIFI_CHINANET_PASS_PLACEHOLDER' ifname wlan0

# 验证
ip addr show wlan0
```

---

## 6. 故障恢复

### 6.1 fastboot 模式都进不去 (硬砖)

```bash
# 1. 按住 音量上 + 音量下 + 电源 进 EDL 模式 (9008)
lsusb | grep 9008
# 期望: 18d1:9008 (Google Inc. EDL)

# 2. 用 QFIL/MiFlash 工具通过 EDL 刷原厂 fastboot 包
# 详见 Xiaomi 官方刷机教程
```

### 6.2 TWRP 救砖

```bash
# 进 fastboot
fb boot twrp-3.7.0_9-0-jason.img
# TWRP 启动后可恢复任意分区
```

### 6.3 modem 分区损坏 (WiFi/基带异常)

```bash
# 刷回 jason 原厂 NON-HLOS.bin (会失去 WiFi 修复)
fb flash modem backups/original-jason-20260627-114354/modem.img
# 或者重新刷 whyred NON-HLOS.bin
fb flash modem /tmp/NON-HLOS-whyred.bin
```

### 6.4 modemst1/modemst2/fsg 损坏 (QMI 协商失败)

```bash
# 必须在 TWRP 下 dd 恢复 (fastboot 不支持这三个分区)
fb boot twrp-3.7.0_9-0-jason.img
sleep 30

ad push backups/original-jason-20260627-114354/modemst1.img /sdcard/
ad push backups/original-jason-20260627-114354/modemst2.img /sdcard/
ad push backups/original-jason-20260627-114354/fsg.img /sdcard/

ad shell dd if=/sdcard/modemst1.img of=/dev/block/bootdevice/by-name/modemst1 bs=4194304
ad shell dd if=/sdcard/modemst2.img of=/dev/block/bootdevice/by-name/modemst2 bs=4194304
ad shell dd if=/sdcard/fsg.img      of=/dev/block/bootdevice/by-name/fsg      bs=4194304
```

---

## 7. 常用命令速查

```bash
# 进入 fastboot (开机状态)
adb reboot bootloader

# 进入 fastboot (pmOS 运行中)
sshpass -p 1234 ssh user@192.168.1.12 "echo 1234 | sudo -S reboot bootloader"
# 或者通过 USB 网络:
sshpass -p 1234 ssh user@172.16.42.1 "echo 1234 | sudo -S reboot bootloader"

# 从 fastboot 切到 recovery (TWRP)
fb oem reboot-recovery

# 从 recovery 切到 fastboot
adb reboot bootloader

# 设备信息
fb getvar all 2>&1 | head -30

# 查看分区
fb getvar partition-type:modem

# 冷启动 pmOS (不刷分区)
fb boot boot-no-debug.img
```

---

## 8. 当前设备状态 (2026-06-28)

- **bootloader**: unlocked
- **modem 分区**: whyred V12 NON-HLOS.bin (WiFi firmware 1.0.0.591)
- **userdata 分区**: pmOS rootfs (xiaomi-jason.img, boot+rootfs 2 分区)
- **其他分区**: jason 原厂
- **网络**: 
  - USB: 172.16.42.1/16 (NCM gadget)
  - WiFi: 192.168.1.12/24 (ChinaNet-810, DHCP 分配)
- **SSH**: user/1234 (USB 或 WiFi 均可)
- **kernel**: 6.19.10-sdm660 (含 PS Mode patch + jason DTS patch)
