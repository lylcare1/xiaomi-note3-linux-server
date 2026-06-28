# D2 fastboot boot 实测启动检查清单

> 阶段: D2 — 临时启动验证 (不 flash 任何分区)
> 设备: Xiaomi Mi Note 3 (jason) / 序列号 `d1236a7b`
> 安全策略: 先 `fastboot boot` 临时验证, OK 后才进入 `fastboot flash`
> 前置: D1 内核 build 已完成

---

## 1. 前置条件检查 (D1 build 成功后)

### 1.1 确认包产物存在

```bash
ls -lh /home/lyl/.local/var/pmbootstrap/packages/edge/aarch64/
```

应至少包含以下三个 apk:

- [ ] `linux-postmarketos-qcom-sdm660-*.apk` (内核包, 含 jason DTS patch)
- [ ] `device-xiaomi-jason-1-r0.apk` (设备包)
- [ ] `firmware-xiaomi-jason-1-r0.apk` (firmware 包, 首阶段可为空壳)

> 若缺失: 回到 D1 检查 `pmbootstrap log` 排查 build 失败原因。

### 1.2 确认 pmbootstrap install 成功

```bash
ls -lh /home/lyl/.local/var/pmbootstrap/chroot_rootfs_xiaomi-jason/home/pmos/rootfs/boot/boot.img 2>/dev/null
ls -lh /home/lyl/.local/var/pmbootstrap/chroot_native/home/pmos/rootfs/boot.img 2>/dev/null
```

- [ ] `boot.img` 存在 (任一路径出现即可, 见 §3)
- [ ] rootfs 镜像存在 (用于后续 `fastboot flash userdata`)

### 1.3 确认设备已连接

```bash
adb devices
# 期望输出:
# d1236a7b  device
```

- [ ] 设备序列号 `d1236a7b` 出现且状态为 `device`
- [ ] 若显示 `unauthorized`: 在手机屏幕上授权 ADB 调试
- [ ] 若无输出: 检查 USB 线 / `adb kill-server && adb start-server`

---

## 2. 设备模式切换

当前设备处于 recovery (TWRP) 模式, 需切到 fastboot。

```bash
# recovery -> fastboot
adb reboot bootloader

# 等待设备进入 fastboot (约 5-10 秒)
sleep 8

# 验证
fastboot devices
# 期望输出:
# d1236a7b  fastboot
```

- [ ] `fastboot devices` 显示 `d1236a7b  fastboot`
- [ ] 若无输出: 检查 USB 是否插稳, 手机屏幕是否显示 fastboot logo (兔子图标)
- [ ] 备用: 拔插 USB 后再试 `fastboot devices`

---

## 3. boot.img 路径确认

> ⚠️ 两份文档记载不一致, 实测前必须 `ls` 确认实际路径。

```bash
# 候选路径 1
ls -lh /home/lyl/.local/var/pmbootstrap/chroot_rootfs_xiaomi-jason/home/pmos/rootfs/boot/boot.img

# 候选路径 2
ls -lh /home/lyl/.local/var/pmbootstrap/chroot_native/home/pmos/rootfs/boot.img

# 推荐方式: 用 pmbootstrap export 导出 (自动定位)
pmbootstrap export
# 会输出类似: (exported) /home/lyl/.local/var/pmbootstrap/chroot_native/home/pmos/rootfs/boot.img
```

- [ ] 确认 `boot.img` 实际路径并记录: __________________
- [ ] 导出后建议复制到工作目录便于引用:
  ```bash
  cp <boot.img 路径> /home/lyl/Documents/system/XiaoMiNote3/boot-jason-test.img
  ```

---

## 4. 安全启动 (fastboot boot, 不 flash)

### 4.1 关于 rootfs 的前置说明

> **关键决策点**: `fastboot boot` 仅加载 kernel+initramfs 到 RAM, 不写分区。
> 但若 rootfs 在 userdata 分区且尚未 flash, 首次 `fastboot boot` 可能无法挂载 rootfs。
>
> 验证策略 (二选一):
>
> - **A. 纯 boot 验证**: 直接 `fastboot boot`, 观察 initramfs 是否启动, USB ethernet 是否出现。即使 rootfs 挂载失败, 也能验证 kernel 与 jason DTS 是否加载。
> - **B. 带 rootfs 验证**: 先 `fastboot flash userdata <rootfs.img>`, 再 `fastboot boot`。能完整验证启动到 shell。
>
> 推荐先执行 A, 若 initramfs 阶段就 panic 再回退检查; 若 initramfs OK 但 rootfs mount 失败, 再执行 B。

### 4.2 方式 A: 直接 fastboot boot (临时, 不写分区)

```bash
# 临时启动到 RAM, 不写任何分区
fastboot boot <boot.img 路径>

# 释放设备 (让内核接管 USB)
# 等待 30-60 秒让 initramfs / init 完成
sleep 45
```

### 4.3 方式 B: 先 flash userdata 再 boot

```bash
# 确认 rootfs.img 路径
ls -lh /home/lyl/.local/var/pmbootstrap/chroot_rootfs_xiaomi-jason/home/pmos/rootfs.img

# flash userdata (rootfs 落盘到 userdata 分区)
fastboot flash userdata <rootfs.img 路径>

# 临时 boot kernel (不 flash boot 分区)
fastboot boot <boot.img 路径>
```

### 4.4 方式 C: 用 pmbootstrap 自动化

```bash
# pmbootstrap 会自动处理 boot.img 路径
pmbootstrap flasher boot
```

- [ ] 执行后观察 fastboot 输出: `OKAY` 表示 boot 命令成功发送
- [ ] 设备重启进入 kernel (屏幕可能黑屏, 这是正常的 — display 不是首阶段必需)

---

## 5. 启动后调试通道 (按优先级)

### 5.1 优先: USB ethernet (developer profile)

pmOS developer profile 会在设备端拉起 USB ethernet, 设备 IP `10.15.19.82`。

```bash
# 主机端先检查 USB 网卡是否出现
ip link
# 期望看到新的 usb 网卡 (通常名为 enpXsY 或 usb0)

# 给主机端 USB 网卡配 IP (网卡名替换为上一步看到的)
sudo ip addr add 10.15.19.100/24 dev <usb网卡名>
sudo ip link set <usb网卡名> up

# 测试连通性
ping -c 3 10.15.19.82

# SSH 登录
ssh user@10.15.19.82
# 密码: 123456 (pmbootstrap install 时设置)
```

### 5.2 备用: pmbootstrap ssh (自动处理路由)

```bash
# pmbootstrap 会自动处理 USB 网卡和路由
pmbootstrap ssh
```

### 5.3 不预期可用

- [x] WiFi 首阶段不可用 (firmware 缺失, 符合预期, 不算故障)

---

## 6. D3 验证检查清单 (启动后执行)

依次在设备端 (SSH 后) 执行:

- [ ] 设备能启动到 Linux shell (USB ethernet 可见, SSH 能连)
- [ ] SSH 可登录: `ssh user@10.15.19.82` (密码 123456)
- [ ] `dmesg` 正常输出, 无严重错误 (重点关注 display / usb / emmc 相关注释)
  ```bash
  dmesg | grep -iE "error|fail|panic|warning" | head -50
  ```
- [ ] `ip a` 能看到 USB ethernet (usb0 或类似, IP 10.15.19.82)
  ```bash
  ip a
  ```
- [ ] `journalctl -b` 完整输出 (systemd 日志可用)
  ```bash
  journalctl -b | tail -100
  ```
- [ ] rootfs 可读写: `mount` 查看 `/` 挂载选项 (应含 `rw`)
  ```bash
  mount | grep ' / '
  ```
- [ ] DTB 生效验证: jason DTB 存在
  ```bash
  ls /boot/dtbs/qcom/sdm660-xiaomi-jason.dtb 2>/dev/null
  # 或运行时 device tree:
  ls /proc/device-tree/ 2>/dev/null
  ```
- [ ] `cat /proc/device-tree/model` 应显示 "Xiaomi Mi Note 3" 或类似
  ```bash
  cat /proc/device-tree/model
  ```
- [ ] 内核版本符合预期 (基于 v6.19.10-sdm660)
  ```bash
  uname -a
  ```
- [ ] eMMC 可见且分区正常
  ```bash
  lsblk
  cat /proc/partitions
  ```

---

## 7. 回退方案 (启动失败时)

### 7.1 快速回退到原厂

```bash
# 在 fastboot 模式下直接重启回原厂系统
# (由于未 flash 任何分区, 原厂系统完整保留)
fastboot reboot
```

### 7.2 回退到 TWRP

```bash
# 临时 boot TWRP (不 flash recovery 分区)
fastboot boot twrp-3.7.0_9-0-jason.img
```

### 7.3 完整恢复原厂 (若已 flash 且失败)

```bash
# 进入原厂 fastboot 包目录
cd jason_images_V8.5.9.0.NCHCNED_20170831.0000.00_7.1_cn/

# 按原厂脚本恢复 (具体脚本名为 flash_all.sh 或类似)
# 或者用备份的 28 个分区逐个 fastboot flash
# 备份位置: backups/original-jason-20260627-114354/
```

> ✅ 安全保障: 本阶段全程使用 `fastboot boot` (不写分区), 原厂系统 + 28 分区备份 + 原厂 fastboot 包三重保障, 任何失败均可回退。

---

## 8. 常见问题排查

| 现象 | 可能原因 | 处理方法 |
|------|---------|---------|
| `fastboot boot` 后黑屏 + 无 USB 设备 | boot.img 配置错误 (deviceinfo_flash_offset_*) | 检查 `deviceinfo_flash_offset_second` 等参数; 对照 jasmine_sprout/lavender 设备包 |
| SSH 连不上 | USB 网卡未出现 / usb-moded 未启动 | 主机端 `lsusb` 看设备是否枚举; `ip link` 看 usb0; 设备端 (若能进) `systemctl status usb-moded` |
| dmesg 报 DRM/display 错误 | 显示驱动问题 (zap shader 缺失等) | **不影响 SSH**, 可忽略; 首阶段 display 非必需 |
| kernel panic | initramfs 缺 jason modules / DTS 未加载 | 用 `fastboot boot` 重试; 检查 initramfs 是否含 `panel-jdi-fhd-r63452` 等模块; 验证 `sdm660-xiaomi-jason.dtb` 是否打包进 boot.img |
| 卡在 boot logo 不动 | kernel 未启动 / earlycon 未配置 | 检查 boot.img 是否含正确 cmdline; 尝试 `fastboot oem boot` 或换用 `pmbootstrap flasher boot` |
| USB ethernet 无 IP | udhcpc 未跑 / network 配置缺失 | 设备端 `rc-service networking restart` 或手动 `ip addr add 10.15.19.82/24 dev usb0` |
| rootfs mount 失败 | userdata 未 flash / 分区格式不对 | 执行 §4.3 方式 B: 先 `fastboot flash userdata <rootfs.img>` |
| `fastboot boot` 报 `FAILED` | boot.img 过大 / 签名问题 | 检查 boot.img 大小 (< 64MB); 确认 bootloader 已解锁 (`fastboot oem device-info` 看 unlocked) |

---

## 执行记录区

> 每次执行 D2 时填写, 留作后续排查依据。

### 执行 #1 (2026-06-27 首次启动)

- 执行日期: 2026-06-27
- D1 build 产物路径: `~/.local/var/pmbootstrap/packages/edge/aarch64/`
- boot.img 实际路径: `/tmp/boot-no-debug.img` (23756800 bytes, 去掉 pmos.debug-shell)
- 采用启动方式 (A/B/C): B (先 flash userdata 再 boot)
- USB ethernet 是否出现: [x] 是 (172.16.42.1/16)
- SSH 是否登录成功: [x] 是 (user/1234)
- 关键 dmesg 输出 / 异常:
  - ABL 拒绝启动 → 修复: DTS patch 添加 qcom,msm-id/board-id/pmic-id
  - USB gadget 需手动配置 (setup-usb-gadget.sh + systemd service)
- 验证清单完成情况: 8 / 10 项 (WiFi 未验证)
- 下一步动作: E1. WiFi firmware 调试

### 执行 #2 (2026-06-28 WiFi 修复后冷启动)

- 执行日期: 2026-06-28
- D1 build 产物路径: 同 #1
- boot.img 实际路径: `/tmp/boot-no-debug.img`
- 采用启动方式 (A/B/C): A (fastboot boot, modem 已刷 whyred NON-HLOS.bin)
- USB ethernet 是否出现: [x] 是 (172.16.42.1/16)
- SSH 是否登录成功: [x] 是 (WiFi 局域网 192.168.1.12)
- 关键 dmesg 输出:
  ```
  [ 41.088853] ath10k_snoc: qmi fw_version 0x101c821a fw_build_id QC_IMAGE_VERSION_STRING=WLAN.HL.1.0.1.c2-00538-QCAHLSWMTPLZ-1.214870.1
  [ 44.202623] ath10k_snoc: firmware 1.0.0.591 booted
  [ 44.241276] ath10k_snoc: htt target version 3.58
  [ 44.242054] ath10k_snoc: htt-ver 3.58 wmi-op 4 htt-op 3 cal file max-sta 32 raw 0 hwcrypto 1
  ```
- 验证清单完成情况: 10 / 10 项 (首阶段 100% 达成)
- 下一步动作: F1. 长稳运行测试 (已完成 30 分钟 0% 丢包)

### 模板 (供后续执行使用)

- 执行日期: ____________
- D1 build 产物路径: __________________
- boot.img 实际路径: __________________
- 采用启动方式 (A/B/C): ____
- USB ethernet 是否出现: [ ] 是 [ ] 否
- SSH 是否登录成功: [ ] 是 [ ] 否
- 关键 dmesg 输出 / 异常:
  ```
  (粘贴关键日志)
  ```
- 验证清单完成情况: ___ / 10 项
- 下一步动作: __________________
