# jason 移植执行计划

> 创建日期: 2026-06-27
> 配套文档: [research.md](./research.md)
> 目标: 将 Xiaomi Mi Note 3 (jason) 移植为可长期运行的 Linux 服务器
> 完成定义: 见 AGENTS.md

## 1. 整体路径

**集成现有社区成果,非原创移植**。

依据调研结论 (见 [research.md](./research.md)),所需组件几乎全部已就绪:

- jason DTS: `alexeymin/jason` 分支已存在 (作者 Kernel114514)
- panel driver: mainline `panel-jdi-fhd-r63452.c` 已合并
- SDM660 通用内核包: pmaports `linux-postmarketos-qcom-sdm660` v6.19.10
- 参考设备包: jasmine_sprout (Mi A2) / lavender (Redmi Note 7) 可作模板
- 原厂固件: 本地 `jason_images_V8.5.9.0.../` 完整 (回退路径)

## 2. 文件清单

### 2.1 新建文件 (4 个)

```
refs/pmaports/device/testing/
├── device-xiaomi-jason/
│   ├── APKBUILD              # 设备包构建脚本
│   ├── deviceinfo            # 设备元信息 (DTB 路径, 屏幕分辨率, boot 参数)
│   └── modules-initfs        # initramfs 加载模块列表
└── firmware-xiaomi-jason/
    └── APKBUILD              # firmware 包构建脚本 (从原厂 NON-HLOS.bin / BTFM.bin 解包)
```

### 2.2 修改文件 (2 个)

```
refs/pmaports/device/testing/linux-postmarketos-qcom-sdm660/
├── APKBUILD                                # 增加 jason DTS source + patch
└── config-postmarketos-qcom-sdm660.aarch64  # 确认 CONFIG_DRM_PANEL_JDI_R63452=y
```

### 2.3 patch 文件 (新增)

```
refs/pmaports/device/testing/linux-postmarketos-qcom-sdm660/
└── 0001-dts-qcom-add-sdm660-xiaomi-jason.patch  # 加入 jason DTS 到 Makefile
```

## 3. 执行步骤

### 阶段 A - 安全准备 (P0, 必须先做)

#### A1. 备份当前 jason 关键分区

**目的**: 保留可回退到原厂系统的路径 (AGENTS.md 强制要求)

**前提**: 设备已临时 boot TWRP (不 flash,保留原厂状态)

**备份清单** (原厂 fastboot 包未包含的运行时分区):

| 分区 | 路径 | 大小 | 必要性 |
|---|---|---|---|
| modemst1 | /dev/block/bootdevice/by-name/modemst1 | 8 MB | 必须 (modem 文件系统) |
| modemst2 | /dev/block/bootdevice/by-name/modemst2 | 8 MB | 必须 (modem 文件系统备份) |
| fsg | /dev/block/bootdevice/by-name/fsg | 8 MB | 必须 (modem 文件系统数据) |
| persist | /dev/block/bootdevice/by-name/persist | 64 MB | 必须 (校准数据) |
| splash | /dev/block/bootdevice/by-name/splash | 64 MB | 推荐 (无原厂镜像) |
| frp | /dev/block/bootdevice/by-name/frp | 1 MB | 可选 (factory reset protection) |
| ssd | /dev/block/bootdevice/by-name/ssd | 32 KB | 可选 (secure device) |
| limits | /dev/block/bootdevice/by-name/limits | 32 KB | 可选 |
| ddr | /dev/block/bootdevice/by-name/ddr | 1 MB | 可选 |

**已有原厂镜像,无需备份** (但建议 dd 验证一致性):
- boot, recovery, system, userdata, cache, cust, modem, dsp, bluetooth, xbl, abl, tz, hyp, rpm, pmic, devcfg, keymaster, cmnlib, cmnlib64, storsec, logo, misc

**脚本位置**: [scripts/backup-partitions.sh](../scripts/backup-partitions.sh)
**备份目标**: `backups/original-jason-YYYYMMDD/`

#### A2. 准备 pmbootstrap 环境

```bash
# 安装 pmbootstrap
apk add pmbootstrap  # 或 pip install --user pmbootstrap

# 初始化工作区
cd /home/lyl/Documents/system/XiaoMiNote3
pmbootstrap init
# 选择 jason 设备 (走 device-xiaomi-jason)
```

### 阶段 B - 创建 device 包 (P0)

#### B1. 创建 device-xiaomi-jason

**模板**: [refs/pmaports/device/testing/device-xiaomi-jasmine_sprout/](../refs/pmaports/device/testing/device-xiaomi-jasmine_sprout/)

**device-xiaomi-jason/deviceinfo** 关键字段 (差异部分):

```sh
deviceinfo_name="Xiaomi Mi Note 3"
deviceinfo_codename="xiaomi-jason"
deviceinfo_year="2017"
deviceinfo_dtb="qcom/sdm660-xiaomi-jason"
deviceinfo_screen_width="1080"
deviceinfo_screen_height="1920"
# 其他字段同 jasmine_sprout
```

**device-xiaomi-jason/APKBUILD** 关键修改:

```
pkgname=device-xiaomi-jason
pkgdesc="Xiaomi Mi Note 3"
depends="
    firmware-xiaomi-jason          # 改: 从 jasmine_sprout 改 jason
    firmware-qcom-adreno-a530
    linux-postmarketos-qcom-sdm660
    mkbootimg
    msm-firmware-loader
    postmarketos-base
    soc-qcom-sdm660
    soc-qcom-sdm660-rproc
"
```

**device-xiaomi-jason/modules-initfs** (基于 jason DTS 实际使用的模块):

```
msm
panel-jdi-fhd-r63452
pm660_fg
pm660_charger
pm660_haptics
qcom-spmi-rradc
```

注: jasmine_sprout 用的 `novatek-nvt-ts`, `panel-novatek-nt36672a`, `pmi8998_fg`, `qcom_smbx` 不适用 jason。

#### B2. 创建 firmware-xiaomi-jason

**模板**: [refs/pmaports/device/testing/firmware-xiaomi-jasmine_sprout/APKBUILD](../refs/pmaports/device/testing/firmware-xiaomi-jasmine_sprout/APKBUILD)

**重要发现 (来自深度研究 [research-deep.md](./research-deep.md))**: 首阶段不需要任何 firmware 文件!
- Debug UART / Display / USB peripheral / eMMC / Volume keys 都由 mainline driver 直接驱动
- GPU zap 缺失只 dev_warn, 不影响 display path
- Modem 不启用 (按 §4.1 决策)
- WiFi 推迟到 P1 阶段

**首阶段 APKBUILD 内容** (空包, 仅依赖占位):
```sh
pkgname=firmware-xiaomi-jason
pkgver=1
pkgrel=0
pkgdesc="Firmware files for Xiaomi Mi Note 3 - minimal initial package"
arch="aarch64"
license="proprietary"
options="!strip !check !archcheck !spdx !tracedeps pmb:cross-native"
package() {
    mkdir -p "$pkgdir"
}
```

**P1 阶段添加的安装文件**:

| 路径 | 用途 | 来源 |
|---|---|---|
| /lib/firmware/ath10k/WCN3990/hw1.0/firmware-5.bin | WiFi 主固件 | ath10k-fwencoder 生成 |
| /lib/firmware/ath10k/WCN3990/hw1.0/board-2.bin | WiFi board 数据 (设备特定) | 从 jason 原厂 BTFM.bin 解包, 或借用 jasmine_sprout |
| /lib/firmware/postmarketos/a512_zap.mbn | GPU zap shader (可选) | 从 jason 原厂 or wayne-common |

**P2 阶段添加** (modem 启用后):
- mba.mbn, modem.mdt, modem.b00 (从原厂 NON-HLOS.bin 解包, 用 qca-swiss-army-knife)
- BT firmware (从 BTFM.bin 解包)

**解包工具**: `qca-swiss-army-knife` (Alpine 包, P1 阶段才需要)

### 阶段 C - 加入 jason DTS 到 kernel 包 (P0)

#### C1. 把 jason DTS 复制到 kernel 包目录

```bash
cp refs/jason-dts/jason.dts \
   refs/pmaports/device/testing/linux-postmarketos-qcom-sdm660/sdm660-xiaomi-jason.dts
```

#### C2. 创建 patch 文件

`0001-dts-qcom-add-sdm660-xiaomi-jason.patch`:
- 添加 `sdm660-xiaomi-jason.dts` 到 `arch/arm64/boot/dts/qcom/`
- 修改 `arch/arm64/boot/dts/qcom/Makefile` 增加:
  ```
  dtb-$(CONFIG_ARCH_QCOM) += sdm660-xiaomi-jason.dtb
  ```

#### C3. 修改 linux-postmarketos-qcom-sdm660/APKBUILD

在 source 列表增加:
```
source="
    linux-$_tag.tar.gz::https://github.com/sdm660-mainline/linux/archive/refs/tags/$_tag.tar.gz
    config-$_flavor.$CARCH
    0001-dts-qcom-add-sdm660-xiaomi-jason.patch
    sdm660-xiaomi-jason.dts
"
```

在 prepare() 增加 patch 应用 + DTS 复制逻辑。

#### C4. 检查内核 config

确认 [config-postmarketos-qcom-sdm660.aarch64](../refs/pmaports/device/testing/linux-postmarketos-qcom-sdm660/config-postmarketos-qcom-sdm660.aarch64) 中:
- `CONFIG_DRM_PANEL_JDI_R63452=m` (当前为 `is not set`, **必改为 =m**)
  - 用 `=m` 而非 `=y`, 因为 modules-initfs 会加载它
  - 这是 jason panel driver, 不启用 panel 不亮
- `CONFIG_ARCH_QCOM=y` (已 OK)
- `CONFIG_DRM_MSM=m` (已 OK)
- `CONFIG_DRM_MSM_DSI_10NM_PHY=y` (已 OK, SDM660 用 10nm PHY)
- `CONFIG_BACKLIGHT_QCOM_WLED=y` (已 OK)
- `CONFIG_USB_DWC3=y` + `CONFIG_USB_DWC3_DUAL_ROLE=y` (已 OK)

### 阶段 D - 构建与测试 (P0)

#### D1. 构建 ✅ 已完成 (2026-06-27 14:31)

详见文末 [§8 D1 完成记录](#8-d1-完成记录-2026-06-27-1431)。

```bash
pmbootstrap build linux-postmarketos-qcom-sdm660
pmbootstrap build device-xiaomi-jason
pmbootstrap build firmware-xiaomi-jason
pmbootstrap install
```

**完成结果**: `firmware-xiaomi-jason` / `postmarketos-base` / `device-xiaomi-jason` 三个包构建成功, 产物位于 `~/.local/var/pmbootstrap/packages/edge/aarch64/`。

#### D2. 实测启动 (临时 boot,不 flash)

```bash
# 先 boot,验证通过再 flash
fastboot boot ~/.local/var/pmbootstrap/chroot_rootfs/home/pmos/rootfs/boot/boot.img

# 或:
pmbootstrap flasher boot
```

#### D3. 验证首阶段成功标准

- [ ] 设备能启动到 Linux shell (USB ethernet 可见)
- [ ] SSH 可登录
- [ ] `dmesg` 正常输出,无严重错误
- [ ] `ip a` 能看到 USB ethernet (usb0)
- [ ] `journalctl -b` 完整
- [ ] rootfs 可读写 (`mount` 看挂载选项)

#### D4. flash 到持久分区

```bash
# 验证通过后:
fastboot flash boot <boot.img>
fastboot flash userdata <rootfs.img>
# 暂不 flash system,因为 pmOS rootfs 在 userdata
fastboot reboot
```

### 阶段 E - WiFi 实测 (P1)

```bash
# 在已启动的 pmOS 中:
nmcli device wifi list
nmcli device wifi connect <SSID> password <PASSWORD>
ip a  # 看是否拿到 wlan0 IP
ping -c 3 8.8.8.8
```

**实测结果 (2026-06-28)**: WiFi firmware 修复后 (whyred NON-HLOS.bin 替换 jason 原厂),firmware 1.0.0.591/htt-ver 3.58 工作正常,wlan0 连接 ChinaNet-810 (192.168.1.12/24),DHCP+IPv6 双栈。详见 [troubleshooting.md](./troubleshooting.md) §7.4-7.5。

### 阶段 F - 文档完善 (P1)

- [x] [docs/reflash-guide.md](./reflash-guide.md) - 刷写/重刷/回退流程 (2026-06-28, 8 章 417 行)
- [x] [docs/troubleshooting.md](./troubleshooting.md) - 常见问题排查 (含 WiFi 调试全过程)
- [x] 更新 AGENTS.md "当前工作进展"
- [x] F1. 长稳运行测试 (2026-06-28, 30 分钟 25 次采样 0% 丢包)

## 4. 关键决策点

### 4.1 是否启用 modem (首阶段)

**初始决策**: 不启用 (P0 阶段)。理由:
- 首阶段目标是 booting+shell+network+ssh
- modem 启动依赖 rproc + firmware + remote filesystem
- 失败可能影响启动稳定性
- USB ethernet + WiFi 已满足网络需求

**最终决策变更 (2026-06-28)**: 实际启用了 modem。理由:
- WiFi (ath10k_snoc WCN3990) firmware 运行在 modem DSP 上,必须启动 modem 才能让 WiFi 工作
- 通过 device-xiaomi-jason depends 加入 `soc-qcom-sdm660-rproc` 依赖
- modem firmware 使用 whyred V12 NON-HLOS.bin (含更新的 wlanmdsp.mbn 1.0.0.591),而非 jason 原厂 (1.0.0.533,会 crash)
- 详见 [troubleshooting.md](./troubleshooting.md) §7.4

**实施**:
- device-xiaomi-jason depends 中加入 `soc-qcom-sdm660-rproc`
- modem 分区刷入 whyred V12 NON-HLOS.bin (覆盖 jason 原厂)
- DTS 中 `&remoteproc_mss` 节点保留 status="okay"

### 4.2 是否启用触控 (首阶段)

**决策**: 不启用。理由:
- SSH 服务器不需要触控
- jason 触控 IC 未知,需拆机或实测确认
- 触控 driver 可能需要单独写

### 4.3 是否启用 GPU 3D 加速

**决策**: 不启用。理由:
- 首阶段无图形界面需求
- Adreno 512 mainline 仅 KMS/fbcon 工作,3D 不完整
- a512_zap.mbn 可启用 GPU KMS,但不影响 SSH

## 5. 回退方案

### 5.1 任何时候回退到原厂

```bash
cd jason_images_V8.5.9.0.NCHCNED_20170831.0000.00_7.1_cn
./flash_all.sh
```

### 5.2 单独恢复某分区

```bash
fastboot flash boot backups/original-jason-YYYYMMDD/boot.img
fastboot flash persist backups/original-jason-YYYYMMDD/persist.img
# 等
```

### 5.3 恢复 modem 文件系统 (若被覆写)

```bash
# 在 TWRP 下:
adb push backups/original-jason-YYYYMMDD/modemst1.img /sdcard/
adb push backups/original-jason-YYYYMMDD/modemst2.img /sdcard/
adb shell dd if=/sdcard/modemst1.img of=/dev/block/bootdevice/by-name/modemst1
adb shell dd if=/sdcard/modemst2.img of=/dev/block/bootdevice/by-name/modemst2
```

## 6. 风险缓解措施

1. **永远先 `fastboot boot` 验证,再 `fastboot flash`**
2. **保留 backups/ 目录至少到首阶段成功**
3. **不 flash xbl/abl/tz/hyp/rpm/pmic/devcfg/keymaster 等底层分区** (原厂已就绪,不需要 pmOS 改)
4. **任何破坏性操作前先记录目的和回滚方式** (AGENTS.md 要求)
5. **失败时优先 `fastboot boot twrp-3.7.0_9-0-jason.img` 进 TWRP 检查**

## 6.5 已澄清问题 (2026-06-27 验证完成)

详见 [research-deep.md §8](./research-deep.md#8-待澄清问题与已澄清答案-2026-06-27-验证) 和 [troubleshooting.md §1](./troubleshooting.md#1-已澄清问题-2026-06-27-验证完成)。

| # | 问题 | 答案 | 影响 |
|---|---|---|---|
| Q1 | `firmware-qcom-adreno-a530` 是否必需? | 严格非必需 (mainline driver 只加载 zap shader), 但保守保留依赖 | 首阶段保留依赖, 实测后可移除 |
| Q2 | jason WiFi board-2.bin 从哪获取? | 借用 jasmine_sprout (同 SoC + 同 WCN3990) | 仅 P1, 不阻塞首阶段 |
| Q3 | `v6.19.10-sdm660` tag 是否含 jason.dts? | **不包含**, 必须完整 patch (DTS + Makefile) | 决定 patch 内容 |
| Q4 | 原厂 bootloader 接受 append_dtb? | 接受 (jasmine_sprout/lavender 同款已验证) | 风险极低 |
| Q5 | append_dtb + flash_offset_second 兼容? | 完全兼容 (jasmine_sprout/lavender 已验证) | 直接复制 jasmine_sprout 配置 |

**附带确认**: `panel-jdi-fhd-r63452.c` driver 已在 tag v6.19.10-sdm660 中, Kconfig/Makefile 都已配置, 无需 patch。只需改 config `CONFIG_DRM_PANEL_JDI_R63452=m`。

## 7. 进度跟踪

参考 [AGENTS.md](../AGENTS.md) 的"当前工作进展"节,完成项实时更新。

- [x] A1. 备份当前 jason 关键分区 (2026-06-27 完成, 28/28 成功, 6.7GB, sha256 校验通过)
- [x] A2. 准备 pmbootstrap 环境 (2026-06-27, init 成功)
- [x] B1. 创建 device-xiaomi-jason (2026-06-27)
- [x] B2. 创建 firmware-xiaomi-jason (2026-06-27, 首阶段为空包)
- [x] C1. 复制 jason DTS (2026-06-27)
- [x] C2. 创建 patch 文件 (2026-06-27)
- [x] C3. 修改 kernel APKBUILD (2026-06-27)
- [x] C4. 检查内核 config (2026-06-27, CONFIG_DRM_PANEL_JDI_R63452=m)
- [x] D1. pmbootstrap build (2026-06-27 14:31, 3 包构建成功, 详见 §8)
- [x] D2. 实测启动 (2026-06-27, kernel 6.19.10-sdm660 进入 pmOS 用户态)
- [x] D3. 验证首阶段成功标准 (2026-06-28, 全部 6 项达成, 详见 troubleshooting.md §7.5)
- [x] D4. flash 到持久分区 (2026-06-27, userdata 写入 xiaomi-jason.img)
- [x] E. WiFi 实测 (2026-06-28, whyred NON-HLOS.bin 修复, fw 1.0.0.591)
- [x] F. 文档完善 (2026-06-28, reflash-guide.md + troubleshooting.md §7.4-7.7)
- [x] F1. 长稳运行测试 (2026-06-28, 30 分钟 0% 丢包)

## 8. D1 完成记录 (2026-06-27 14:31)

**构建成功包列表**:

| 包名 | 状态 | 备注 |
|---|---|---|
| firmware-xiaomi-jason | Done! | 1227 bytes |
| postmarketos-base | Done! | 依赖包 |
| device-xiaomi-jason | Done! | 2599 bytes |

**包产物路径**: `~/.local/var/pmbootstrap/packages/edge/aarch64/`
- `device-xiaomi-jason-1-r0.apk` (2599 bytes)
- `firmware-xiaomi-jason-1-r0.apk` (1227 bytes)

**遇到的问题**:
- `crossdirect` 包曾因 HTTP 502 失败一次 (代理临时故障)
- 解决方式: 重试 `pmbootstrap build` 即成功

**下一步**:
- `pmbootstrap install` (构建完整 rootfs, 含内核 build) — 正在后台运行
- D2: `fastboot boot` 实测启动
- D3: 验证首阶段成功标准
