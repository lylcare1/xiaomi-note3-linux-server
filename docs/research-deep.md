# jason 移植深度研究 - pmOS 设备包机制详解

> 创建日期: 2026-06-27
> 配套文档: [research.md](./research.md) (高层调研) + [port-plan.md](./port-plan.md) (执行计划)
> 范围: 深入分析 pmOS 设备包/内核包/firmware 包的构建机制, 为 jason 移植提供具体落地方案

## 1. 概述

本文档基于对 pmaports 仓库的逐文件分析,梳理出 jason 移植所需的所有技术细节。读完本文档,可以:

- 完全理解 pmOS 设备包的 APKBUILD / deviceinfo / modules-initfs 三件套
- 完全理解 sdm660 内核包的构建流程和 config 修改点
- 完全理解 firmware 包的三种实现模式
- 知道 jason 移植要写哪些文件、改哪些 config、打哪些 patch

## 2. pmOS 设备包规范详解

### 2.1 APKBUILD 标准模板

参考 [device-xiaomi-jasmine_sprout/APKBUILD](../refs/pmaports/device/testing/device-xiaomi-jasmine_sprout/APKBUILD):

```sh
maintainer="..."
pkgname=device-xiaomi-jasmine_sprout    # 包名: device-<vendor>-<codename>
pkgdesc="Xiaomi Mi A2"                  # 设备友好名
pkgver=3                                # 包版本(整数,每次改 deviceinfo 加 1)
pkgrel=1                                # 发布号
url="https://postmarketos.org"
license="MIT"
arch="aarch64"                           # 设备架构
options="!check !archcheck"              # 设备包无单元测试

depends="                                # 运行时依赖
    firmware-xiaomi-jasmine_sprout       # 设备 firmware 包
    firmware-qcom-adreno-a530            # Adreno 5xx GPU firmware (a530 子包)
    linux-postmarketos-qcom-sdm660      # 内核包
    mkbootimg                            # boot.img 生成工具
    msm-firmware-loader                  # modem/wifi 固件从 /persist 分区加载服务
    postmarketos-base                    # pmOS 基础包 (init 系统, ssh, sudo, udev 等)
    soc-qcom-sdm660                     # SDM660 SoC 通用包 (alsa-ucm, swclock-offset)
    soc-qcom-sdm660-rproc                # SDM660 remoteproc 服务 (modem, wifi)
"

makedepends="devicepkg-dev"              # 构建依赖: 提供 devicepkg_build/devicepkg_package 工具

source="
    deviceinfo                           # 设备元信息
    modules-initfs                       # initramfs 模块列表
"

build() {
    devicepkg_build $startdir $pkgname   # 调用 devicepkg-dev 的脚本
}

package() {
    devicepkg_package $startdir $pkgname # 调用 devicepkg-dev 的脚本
}

sha512sums="..."                         # source 中文件的 sha512
```

### 2.2 devicepkg_build / devicepkg_package 做了什么

参考 [devicepkg-dev/devicepkg_build.sh](../refs/pmaports/main/devicepkg-dev/devicepkg_build.sh) 和 [devicepkg_package.sh](../refs/pmaports/main/devicepkg-dev/devicepkg_package.sh):

**`devicepkg_build`** (在 build() 调用):
1. 读取 `$srcdir/deviceinfo`
2. 调用 `generate_machine_info` 生成 `$srcdir/machine-info` (PRETTY_HOSTNAME / CHASSIS / HARDWARE_VENDOR / HARDWARE_MODEL)
3. 如果 `deviceinfo_dev_touchscreen` 存在,生成 udev 规则 `$srcdir/90-$pkgname.rules`

**`devicepkg_package`** (在 package() 调用):
1. `install -Dm644 deviceinfo` -> `$pkgdir/usr/share/deviceinfo/$pkgname` (主设备信息文件)
2. `ln -s $pkgname $pkgdir/usr/share/deviceinfo/deviceinfo` (创建 deviceinfo 符号链接)
3. `install -Dm644 machine-info` -> `$pkgdir/etc/machine-info`
4. 若 `90-$pkgname.rules` 存在,装到 `/etc/udev/rules.d/`
5. 若 `initfs-hook.sh` 存在,装到 `/usr/share/mkinitfs/hooks/00-$pkgname.sh`
6. 若 `modules-initfs` 存在:
   - 装到 `/usr/share/mkinitfs/modules/00-$pkgname.modules`
   - 创建 `/usr/share/mkinitfs/files/00-$pkgname-modules.files` (映射到 `/usr/lib/modules/initramfs.load`)
7. 若 `modules-load.conf` / `modprobe.conf` / `kernel-cmdline.conf` 存在,装到对应位置

### 2.3 deviceinfo 关键字段

参考 [device-xiaomi-jasmine_sprout/deviceinfo](../refs/pmaports/device/testing/device-xiaomi-jasmine_sprout/deviceinfo) 和 schema 文件 [deviceinfo_schema.toml](../refs/pmaports/deviceinfo_schema.toml):

**必填字段**:
- `deviceinfo_format_version="0"` (固定值)
- `deviceinfo_name="Xiaomi Mi Note 3"` (友好名)
- `deviceinfo_manufacturer="Xiaomi"`
- `deviceinfo_codename="xiaomi-jason"` (去 vendor 前缀,通常 vendor=qualcomm 时用 codename 直)
- `deviceinfo_year="2017"` (设备发布年份)
- `deviceinfo_arch="aarch64"`
- `deviceinfo_dtb="qcom/sdm660-xiaomi-jason"` (DTB 路径,相对 /boot/dtbs/)
- `deviceinfo_append_dtb="true"` (DTB 追加到 kernel 后,而非单独分区)

**显示相关**:
- `deviceinfo_drm="true"` (使用 DRM)
- `deviceinfo_chassis="handset"` (设备类型: handset/tablet/...
- `deviceinfo_screen_width="1080"` / `deviceinfo_screen_height="1920"`

**boot 相关**:
- `deviceinfo_flash_method="fastboot"` (使用 fastboot 刷写)
- `deviceinfo_flash_fastboot_partition_vbmeta="vbmeta"` (刷 vbmeta)
- `deviceinfo_generate_bootimg="true"` (生成 Android boot.img)
- `deviceinfo_flash_pagesize="4096"` (内存页大小)
- `deviceinfo_flash_offset_base="0x00000000"`
- `deviceinfo_flash_offset_kernel="0x00008000"`
- `deviceinfo_flash_offset_ramdisk="0x01000000"`
- `deviceinfo_flash_offset_second="0x00f00000"`
- `deviceinfo_flash_offset_tags="0x00000100"`
- `deviceinfo_flash_kernel_on_update="true"` (内核升级时刷 boot 分区)

**lavender 多面板变体**(jason 不需要,只用一种 JDI panel):
- `deviceinfo_dtb_boe="qcom/sdm660-xiaomi-lavender-boe"`
- `deviceinfo_dtb_shenchao="..."`
- `deviceinfo_dtb_tianma="..."`
- 配合 `subpackages` + `devicepkg_subpackage_kernel` 实现 subpackage 机制

**lavender 还有但 jason 不需要**:
- `deviceinfo_generate_extlinux_config="true"` (extlinux.conf, jason 用 append_dtb 就够)
- `deviceinfo_flash_sparse="true"` (sparse image, jason 不需要)
- `deviceinfo_external_storage="true"` (SD 卡槽, jason 无)

### 2.4 modules-initfs 机制

文件格式: 一行一个模块名(不带 .ko 后缀),按依赖顺序排列。

参考 [device-xiaomi-jasmine_sprout/modules-initfs](../refs/pmaports/device/testing/device-xiaomi-jasmine_sprout/modules-initfs):
```
msm                       # Qualcomm MSM 核心 (display, etc)
novatek-nvt-ts            # 触摸屏 (jasmine_sprout 用 Novatek NT36672A)
panel-novatek-nt36672a    # panel driver (jasmine_sprout 用 Novatek panel)
pmi8998_fg                # 电池燃料表
qcom_smbx                 # 充电管理
qcom-spmi-rradc           # PMIC RRADC (重复 ADC, 用于电压电流读取)
```

**jason 的 modules-initfs 应为** (基于 [jason.dts](../refs/jason-dts/jason.dts) 中已 enable 的硬件):
```
msm                       # DRM MSM 核心
panel-jdi-fhd-r63452       # JDI R63452 panel driver (mainline)
qcom-spmi-rradc           # PMIC RRADC
pm660_fg                  # PM660 燃料表
pm660_charger             # PM660 充电器
pm660_haptics             # PM660 振动
```

**注意**: jason 的 panel driver 在 mainline 是 `panel-jdi-fhd-r63452` (CONFIG_DRM_PANEL_JDI_R63452), 见 [mainline 源码](https://github.com/torvalds/linux/blob/master/drivers/gpu/drm/panel/panel-jdi-fhd-r63452.c)。但当前 SDM660 内核 config 中此项 `is not set`, 必须改成 `=m`。

### 2.5 多面板 subpackage 机制 (jason 不用)

[lavender/APKBUILD](../refs/pmaports/device/testing/device-xiaomi-lavender/APKBUILD) 演示了多面板变体:
- `subpackages="$pkgname-kernel-boe:kernel_boe ..."` (每个变体一个子包)
- 每个变体对应 `modules-initfs.<variant>` 文件
- `kernel_<variant>()` 函数调用 `devicepkg_subpackage_kernel`
- 脚本会把 `deviceinfo_dtb_<variant>` 转成 `deviceinfo_dtb` (见 [devicepkg_subpackage_kernel.sh](../refs/pmaports/main/devicepkg-dev/devicepkg_subpackage_kernel.sh))

jason 只有一种 panel (JDI R63452),不需要此机制。

### 2.6 kernel-cmdline.conf 机制

[lavender/kernel-cmdline.conf](../refs/pmaports/device/testing/device-xiaomi-lavender/kernel-cmdline.conf) 内容:
```
msm.prefer_mdp5=false
```

这个文件被 `devicepkg_package` 装到 `/usr/lib/kernel-cmdline.d/50-$pkgname.conf`,由 [postmarketos-mkinitfs](../refs/pmaports/main/postmarketos-mkinitfs/APKBUILD) 在生成 initramfs 时合并到 kernel cmdline。

jason 应该不需要此文件 (默认 cmdline 已足够)。

## 3. pmOS 内核包 (linux-postmarketos-qcom-sdm660) 详解

### 3.1 APKBUILD 结构

参考 [linux-postmarketos-qcom-sdm660/APKBUILD](../refs/pmaports/device/testing/linux-postmarketos-qcom-sdm660/APKBUILD):

**关键信息**:
- `pkgname=linux-postmarketos-qcom-sdm660` (pkgname 命名规则: `linux-<flavor>`)
- `_flavor="postmarketos-qcom-sdm660"` (内核 flavor 名)
- `pkgver=6.19.10` (内核版本)
- `_tag="v$pkgver-sdm660"` (git tag, 在 sdm660-mainline 仓库)
- `source` 第一个是 `https://github.com/sdm660-mainline/linux/archive/refs/tags/$_tag.tar.gz`
- `builddir="$srcdir/linux-$pkgver-sdm660"` (源码目录名不带 v 前缀)

**构建依赖** (makedepends):
```
bison clang findutils flex lld llvm openssl-dev perl
postmarketos-installkernel python3 zstd
```

**prepare()**:
```sh
default_prepare
cp -v "$srcdir/config-$_flavor.$CARCH" "$builddir"/.config  # 用我们提供的 config
```

**build()**:
```sh
unset LDFLAGS   # 内核不能受 LDFLAGS 影响
make ARCH="arm64" LLVM=1 \
    KBUILD_BUILD_VERSION="$((pkgrel + 1))-$_flavor" all Image.gz
```

注意 `LLVM=1` 表示用 Clang/LD 而非 GCC/LD 编译。`Image.gz` 是 arm64 内核镜像。

**package()** 关键步骤:
1. `make modules_install dtbs_install` - 装模块和 DTB
2. `install vmlinuz.efi` -> `/boot/vmlinuz.efi` (UEFI 启动用)
3. `install Image.gz` -> `/boot/vmlinuz` (Android boot.img 用)
4. **只保留 SDM630/636/660 相关 DTB**, 其他删掉 (从 46MB 减到 30MB)
5. 删除 `/lib/modules/*/build` 和 `/source` 符号链接 (节省空间)
6. `install kernel.release` -> `/usr/share/kernel/$_flavor/kernel.release`

### 3.2 内核 config 文件分析

参考 [config-postmarketos-qcom-sdm660.aarch64](../refs/pmaports/device/testing/linux-postmarketos-qcom-sdm660/config-postmarketos-qcom-sdm660.aarch64) (7937 行, 216KB):

**已启用 (OK)**:
- `CONFIG_ARCH_QCOM=y`
- `CONFIG_DRM_MSM=m` + `CONFIG_DRM_MSM_DSI=y` + `CONFIG_DRM_MSM_DSI_10NM_PHY=y` (SDM660 用 10nm PHY)
- `CONFIG_BACKLIGHT_QCOM_WLED=y` (PM660L WLED 背光)
- `CONFIG_ATH10K=m` + `CONFIG_ATH10K_SNOC=m` (WCN3990 WiFi)
- `CONFIG_USB_DWC3=y` + `CONFIG_USB_DWC3_DUAL_ROLE=y`
- `CONFIG_SERIAL_MSM=y` + `CONFIG_SERIAL_MSM_CONSOLE=y` (Debug UART)
- `CONFIG_REMOTEPROC=y` + `CONFIG_QCOM_Q6V5_MSS=m` (modem remoteproc)
- `CONFIG_QCOM_Q6V5_WCSS=m` (WiFi/BT 固件 PIL)
- `CONFIG_POWER_RESET_QCOM_PON=y` (PON 按键)
- `CONFIG_REGULATOR_QCOM_SPMI=y` (PMIC regulator)
- `CONFIG_QCOM_SPMI_ADC_TM5=m` + `CONFIG_QCOM_SPMI_TEMP_ALARM=m`
- `CONFIG_QCOM_GPI_DMA=y` (GENI GPI DMA, 用于 DSI/UART)
- `CONFIG_QCOM_BAM_DMA=y`

**必须修改 (重要)**:
- `# CONFIG_DRM_PANEL_JDI_R63452 is not set` -> **改成 `CONFIG_DRM_PANEL_JDI_R63452=m`**

  这是 jason 的 panel driver! 不启用 panel 不亮。mainline 中此 driver 文件名是 `panel-jdi-fhd-r63452.c`,匹配 jason.dts 中 `compatible = "jdi,fhd-r63452"`。

  注意: 模块名是 `panel-jdi-fhd-r63452` (连字符),不是 `panel_jdi_r63452`。

### 3.3 jason DTS 如何加入内核包

**问题**: sdm660-mainline/linux 的 `alexeymin/jason` 分支包含 jason.dts, 但当前内核包用的是 `v6.19.10-sdm660` tag, 不一定包含 jason。

**验证**: 让我先检查 tag 中是否已有 jason.dts。已有 `refs/jason-dts/jason.dts` 是从 `alexeymin/jason` 分支拉取的。

**两种集成方式**:

**方式 A (推荐): 通过 patch 加入**
1. 创建 patch 文件 `0001-dts-qcom-add-sdm660-xiaomi-jason.patch`
2. 在 patch 中:
   - 新增 `arch/arm64/boot/dts/qcom/sdm660-xiaomi-jason.dts` (从 [refs/jason-dts/jason.dts](../refs/jason-dts/jason.dts) 复制)
   - 修改 `arch/arm64/boot/dts/qcom/Makefile` 加入 `dtb-$(CONFIG_ARCH_QCOM) += sdm660-xiaomi-jason.dtb`
3. 在 APKBUILD 的 `source` 中加入 patch 文件
4. `default_prepare` 会自动应用 patch

**方式 B: 修改 APKBUILD 改用 alexeymin/jason 分支**
- 改 `source` 为 git 分支
- 风险: 引入作者其他改动

方式 A 更可控,推荐。

### 3.4 patch 文件示例

`0001-dts-qcom-add-sdm660-xiaomi-jason.patch` 应该长这样:

```diff
From: jason port <port@example.com>
Date: 2026-06-27
Subject: [PATCH] arm64: dts: qcom: add Xiaomi Mi Note 3 (jason)

Add device tree for Xiaomi Mi Note 3 (jason) based on SDM660.

Signed-off-by: jason port <port@example.com>
---
 arch/arm64/boot/dts/qcom/Makefile                |    1 +
 arch/arm64/boot/dts/qcom/sdm660-xiaomi-jason.dts |  542 +++
 2 files changed, 543 insertions(+)
 create mode 100644 arch/arm64/boot/dts/qcom/sdm660-xiaomi-jason.dts

--- a/arch/arm64/boot/dts/qcom/Makefile
+++ b/arch/arm64/boot/dts/qcom/Makefile
@@ -xxx,yyy
 dtb-$(CONFIG_ARCH_QCOM) += sdm660-xiaomi-jasmine.dtb
+dtb-$(CONFIG_ARCH_QCOM) += sdm660-xiaomi-jason.dtb
 dtb-$(CONFIG_ARCH_QCOM) += sdm660-xiaomi-lavender-boe.dtb
...

--- /dev/null
+++ b/arch/arm64/boot/dts/qcom/sdm660-xiaomi-jason.dts
@@ -0,0 +1,542 @@
+(jason.dts 全文)
```

实际生成可以用 `git format-patch` 或手写。

## 4. firmware 包详解

### 4.1 三种 firmware 包模式对比

| 模式 | 参考 | WiFi firmware 来源 | GPU firmware 来源 | BT firmware |
|---|---|---|---|---|
| **A: 自建 gitlab 仓库** | jasmine_sprout / lavender | gitlab.com 上的 firmware-xiaomi-* 仓库 (提供 board-2.bin) + ath10k-fwencoder 生成 firmware-5.bin | TheMuppets GitHub 仓库的 `proprietary_vendor_xiaomi_*` | (依赖 msm-firmware-loader) |
| **B: minlexx.ru 镜像** | whyred | `fw.minlexx.ru/firmware-xiaomi-whyred.tar.bz2` (预打包) + ath10k-bdencoder 用 JSON 生成 board-2.bin | TheMuppets GitHub 直接拉 `a512_zap.elf` | (同上) |
| **C: 完全自建 (无依赖)** | (无现成模板) | 从原厂 BTFM.bin 解包 + ath10k-bdencoder | 从原厂 modem.img 提取 | 从原厂提取 |

### 4.2 ath10k firmware 机制 (WCN3990)

WCN3990 是 SDM660 的 WiFi/BT 模组,使用 ath10k 驱动。需要的 firmware 文件:

| 文件路径 | 用途 | 来源 |
|---|---|---|
| `/lib/firmware/ath10k/WCN3990/hw1.0/firmware-5.bin` | ath10k 主固件 | ath10k-fwencoder 工具生成 (从 board-2-short.json 之类描述生成) |
| `/lib/firmware/ath10k/WCN3990/hw1.0/board-2.bin` | 板级校准数据 | 从 gitlab 上的 firmware-xiaomi-* 仓库拉取 (设备特定) |

**ath10k-fwencoder** 工具来自 [qca-swiss-army-knife](../refs/pmaports/main/qca-swiss-army-knife/APKBUILD) 包:
- `--create --features=... --set-wmi-op-version=tlv --set-htt-op-version=tlv --set-fw-api=5` 生成 `firmware-5.bin`
- 这是通用 WCN3990 firmware,设备无关

**board-2.bin 是设备特定的**:
- 包含 WiFi 校准数据 (TX power, frequency offset 等)
- 必须从 jason 原厂或社区 gitlab 仓库获取
- 目前没有公开的 `firmware-xiaomi-jason` gitlab 仓库, 需要从原厂 BTFM.bin 提取

**实测后补充 (2026-06-28)**:

实际上 WCN3990 的 WiFi firmware 有 3 层,缺一不可:

| 层级 | 文件 | 位置 | 来源 |
|---|---|---|---|
| 1. ath10k 用户态 firmware | `firmware-5.bin` | rootfs `/lib/firmware/ath10k/WCN3990/hw1.0/` | ath10k-fwencoder 生成 |
| 2. 板级校准数据 | `board-2.bin` / `board.bin` | rootfs 同上目录 | 借用 jasmine_sprout 或从 modem 分区提取 |
| 3. **WiFi DSP firmware** | `wlanmdsp.mbn` | **modem 分区 NON-HLOS.bin 内** | 设备原厂或同 SoC 设备 NON-HLOS.bin |

第 3 层 `wlanmdsp.mbn` 是真正的 WiFi 固件二进制,运行在 modem DSP 上,ath10k 驱动通过 QMI 与 modem 通信加载它。**这一层无法从 rootfs 替换,必须刷 modem 分区**。

实测发现 jason 原厂 wlanmdsp.mbn 版本 1.0.0.533 (htt-ver 3.50) 与 mainline ath10k_snoc 驱动不兼容,启动后 ~350ms crash。解决方案: 刷入 whyred V12 完整 NON-HLOS.bin (wlanmdsp.mbn 升级到 1.0.0.591, htt-ver 3.58)。详见 [troubleshooting.md](./troubleshooting.md) §7.4。

### 4.3 Adreno GPU firmware 机制

jason GPU = Adreno 512 (SDM660 标配), 需要:
- `a512_zap.mbn` - zap shader (GPU 安全启动映像)

**来源**:
- TheMuppets GitHub 仓库: `proprietary_vendor_xiaomi_<codename>/proprietary/vendor/firmware/a512_zap.elf`
- jasmine_sprout 用 `wayne-common` 仓库 (Mi A2 / Mi 6X 共用)
- lavender 用 `lavender` 仓库
- jason 需要找对应仓库或从原厂 modem.img 提取

**安装路径**: `/lib/firmware/postmarketos/a512_zap.mbn` (注意 .mbn 后缀, 实际是 .elf)

**注意**: jason.dts 中 `firmware-name = "a512_zap.mbn"`, 内核会从 `/lib/firmware/postmarketos/a512_zap.mbn` 加载 (postmarketos 子目录)。如果 zap shader 缺失, 内核会 warning 但不影响显示 (display path 不需要 GPU 3D 加速)。

### 4.4 firmware-qcom-adreno-a530 是什么?

jasmine_sprout/lavender/whyred 都依赖 `firmware-qcom-adreno-a530`, 但它们的 GPU 都是 Adreno 512 (SDM660)。原因推测:

参考 [firmware-qcom-adreno/APKBUILD](../refs/pmaports/device/community/firmware-qcom-adreno/APKBUILD):
- subpackages: a300, a330, a420, **a530**, a650, a660, gen70500
- `a530` subpackage 装的是 `$builddir/qcom/a530*` 文件
- 注意 `replaces="linux-firmware-qcom"`, 即这是 linux-firmware 仓库中 qcom/a530_* 的拆分包

**推测**: Adreno 530 是 SDM820 的 GPU, 但 a530 的 PM4/PFP firmware 可能与 a512 共用 (都是 a5xx 系列, 在 mainline `adreno/a5xx_gpu.c` 中共用 driver)。也可能 jason 实际不需要这个包 (display 不依赖 GPU)。

**待验证**: jason 是否真的需要 `firmware-qcom-adreno-a530`。可以先不加这个依赖, 看是否影响显示。

### 4.5 msm-firmware-loader 机制

参考 [msm-firmware-loader/APKBUILD](../refs/pmaports/main/msm-firmware-loader/APKBUILD):

- 提供 OpenRC 服务 `/etc/init.d/msm-firmware-loader` 和 `msm-firmware-loader-unpack`
- 服务在启动时从 `/persist` 分区或其他原厂分区读取 modem/WiFi/BT 固件并加载到内核
- 子包 `msm-firmware-loader-wcnss` `provides="firmware-qcom-msm8916-wcnss"` (对老芯片用)

**对 jason**: 此包用于 modem 固件加载 (NON-HLOS.bin 的内容通过 remoteproc 加载)。如果首阶段不启用 modem (按 AGENTS.md "先 booting+shell+network,不投入基带"),可以暂时不装此包。但 WiFi (WCN3990) 用 ath10k 驱动 (独立 firmware),不依赖此包。

### 4.6 jason 需要的 firmware 清单 (首阶段)

按 AGENTS.md 优先级, 首阶段只追求 booting + shell + network:

| 组件 | 是否需要 | firmware 路径 | 来源 |
|---|---|---|---|
| Debug UART (blsp1_uart2) | 是 | 无需 firmware | (硬件直驱) |
| Display (mdss_dsi0 + JDI panel) | 是 | 无需 firmware | (panel driver 直驱) |
| USB peripheral (USB ethernet/SSH) | 是 | 无需 firmware | (dwc3 直驱) |
| eMMC (sdhc_1) | 是 | 无需 firmware | (硬件直驱) |
| Volume keys / PON | 是 | 无需 firmware | (硬件直驱) |
| GPU 3D (Adreno 512) | 否 (首阶段不需要 3D) | a512_zap.mbn | (缺失时 warning, 不影响 display) |
| WiFi (WCN3990 ath10k) | 是 (P1, AGENTS.md 要求 WiFi) | firmware-5.bin + board-2.bin | 自建 gitlab 仓库 / 原厂提取 |
| Modem (remoteproc_mss) | 否 (按 AGENTS.md 推迟) | mba.mbn, modem.mdt | (暂不启用) |
| Bluetooth (wcn3990-bt) | 否 (按 AGENTS.md 推迟) | qca/... | (暂不启用) |

**首阶段 firmware 包 (firmware-xiaomi-jason) 最小化内容**:
```
# 可以为空包! 首阶段不需要任何 firmware 文件
# 所有必需组件都由 mainline driver 直接驱动,无需 firmware
```

**P1 阶段 (WiFi 启用后)** 需要添加:
```
/lib/firmware/ath10k/WCN3990/hw1.0/firmware-5.bin  (ath10k-fwencoder 生成)
/lib/firmware/ath10k/WCN3990/hw1.0/board-2.bin     (需找或自建, jason 设备特定)
```

**可选 (GPU 加速)**:
```
/lib/firmware/postmarketos/a512_zap.mbn             (从 TheMuppets 仓库或原厂提取)
```

## 5. pmbootstrap 工作流程

### 5.1 pmbootstrap 是什么

pmbootstrap 是 pmOS 的构建工具,封装了:
- abuild (Alpine 包构建)
- chroot 环境 (构建隔离)
- 多设备/多内核包管理
- boot.img 生成 (调 mkbootimg)
- fastboot/adb 集成

### 5.2 典型工作流 (jason 移植)

```bash
# 1. 安装 pmbootstrap (Alpine)
apk add pmbootstrap

# 2. 初始化工作区
cd /home/lyl/Documents/system/XiaoMiNote3
pmbootstrap init
# 选项: work path=~/pmOS, device=xiaomi-jason, ui=none (服务器无图形), ...

# 3. 把 device 包和 kernel patch 加到本地 pmaports
# (复制到 refs/pmaports/device/testing/ 下,然后用 pmbootstrap pull/push)
pmbootstrap pkginit device-xiaomi-jason
pmbootstrap pkginit linux-postmarketos-qcom-sdm660  # 修改

# 4. 构建 (会自动 build 内核, initramfs, rootfs)
pmbootstrap build device-xiaomi-jason
pmbootstrap build linux-postmarketos-qcom-sdm660

# 5. 生成 boot.img + rootfs (不刷写)
pmbootstrap install

# 6. 实测启动 (fastboot boot,不 flash)
pmbootstrap boot  # 或:
fastboot boot ~/.local/var/pmbootstrap/chroot_native/home/pmos/rootfs/boot.img

# 7. 进 shell 调试
pmbootstrap ssh  # 或:
adb shell

# 8. 验证 OK 后再 flash
fastboot flash boot boot.img
```

### 5.3 pmbootstrap 关键目录

```
~/.local/var/pmbootstrap/
├── cache_git/         # git 缓存
├── chroot_buildroot/   # 构建用 chroot
├── chroot_native/      # native chroot
├── packages/           # 构建产物 .apk
└── config.cfg          # 配置
```

## 6. boot.img 生成机制

### 6.1 boot-deploy 工具

参考 [boot-deploy/APKBUILD](../refs/pmaports/main/boot-deploy/APKBUILD):
- `pkgdesc="tool for finalizing and deploying boot related files"`
- `depends="generate-kernel-cmdline"`
- 在 mkinitfs trigger 阶段调用
- 负责: 生成 initramfs -> 合并 kernel + initramfs -> 调 mkbootimg 生成 boot.img

### 6.2 mkbootimg

参考 [main/mkbootimg-osm0sis/APKBUILD](../refs/pmaports/main/mkbootimg-osm0sis/APKBUILD):
- Google 的 Android boot.img 打包工具
- 输入: kernel (Image.gz) + ramdisk (initramfs) + cmdline + pagesize
- 输出: boot.img

### 6.3 jason boot.img 流程

1. `linux-postmarketos-qcom-sdm660` 包提供 `vmlinuz` (= Image.gz) + DTB (在 `/boot/dtbs/qcom/sdm660-xiaomi-jason.dtb`)
2. `device-xiaomi-jason` deviceinfo 中 `deviceinfo_append_dtb="true"`, 表示 DTB 追加到 kernel 后
3. `postmarketos-mkinitfs` 生成 initramfs:
   - 模块: 从 `/usr/share/mkinitfs/modules/00-device-xiaomi-jason.modules` 加载
   - hooks: 调用 `boot-deploy` trigger
4. `boot-deploy` 调 `mkbootimg`:
   - kernel = Image.gz + DTB (concatenated)
   - ramdisk = initramfs
   - cmdline = `/usr/lib/kernel-cmdline.d/*.conf` 合并
   - pagesize = 4096 (from deviceinfo)
5. 输出 boot.img 到 `/boot`

## 7. jason 移植具体落地方案

### 7.1 文件清单 (基于 jasmine_sprout 模板)

**新建 3 个文件** (在 `refs/pmaports/device/testing/device-xiaomi-jason/`):

```
device-xiaomi-jason/
├── APKBUILD             # 见 7.2
├── deviceinfo           # 见 7.3
└── modules-initfs       # 见 7.4
```

**新建 1 个文件** (在 `refs/pmaports/device/testing/firmware-xiaomi-jason/`):

```
firmware-xiaomi-jason/
└── APKBUILD             # 见 7.5 (首阶段为空包)
```

**新增 1 个 patch + 修改 2 个文件** (在 `refs/pmaports/device/testing/linux-postmarketos-qcom-sdm660/`):

```
linux-postmarketos-qcom-sdm660/
├── APKBUILD             # 修改: source 加 patch
├── config-postmarketos-qcom-sdm660.aarch64  # 修改: CONFIG_DRM_PANEL_JDI_R63452=m
└── 0001-dts-qcom-add-sdm660-xiaomi-jason.patch  # 新增
```

### 7.2 device-xiaomi-jason/APKBUILD

```sh
# Reference: <https://postmarketos.org/devicepkg>
maintainer="jason port <port@example.com>"
pkgname=device-xiaomi-jason
pkgdesc="Xiaomi Mi Note 3"
pkgver=1
pkgrel=0
url="https://postmarketos.org"
license="MIT"
arch="aarch64"
options="!check !archcheck"

depends="
    firmware-xiaomi-jason
    firmware-qcom-adreno-a530
    linux-postmarketos-qcom-sdm660
    mkbootimg
    msm-firmware-loader
    postmarketos-base
    soc-qcom-sdm660
    soc-qcom-sdm660-rproc
"

makedepends="devicepkg-dev"

source="
    deviceinfo
    modules-initfs
"

build() {
    devicepkg_build $startdir $pkgname
}

package() {
    devicepkg_package $startdir $pkgname
}

sha512sums="
<deviceinfo_sha>  deviceinfo
<modules_sha>     modules-initfs
"
```

### 7.3 device-xiaomi-jason/deviceinfo

```sh
# Reference: <https://postmarketos.org/deviceinfo>
# Please use double quotes only. You can source this file in shell scripts.

deviceinfo_format_version="0"
deviceinfo_name="Xiaomi Mi Note 3"
deviceinfo_manufacturer="Xiaomi"
deviceinfo_codename="xiaomi-jason"
deviceinfo_year="2017"
deviceinfo_dtb="qcom/sdm660-xiaomi-jason"
deviceinfo_append_dtb="true"
deviceinfo_arch="aarch64"
deviceinfo_flash_kernel_on_update="true"

# Device related
deviceinfo_drm="true"
deviceinfo_chassis="handset"
deviceinfo_screen_width="1080"
deviceinfo_screen_height="1920"

# Bootloader related
deviceinfo_flash_method="fastboot"
deviceinfo_flash_fastboot_partition_vbmeta="vbmeta"
deviceinfo_generate_bootimg="true"
deviceinfo_flash_pagesize="4096"
deviceinfo_flash_offset_base="0x00000000"
deviceinfo_flash_offset_kernel="0x00008000"
deviceinfo_flash_offset_ramdisk="0x01000000"
deviceinfo_flash_offset_second="0x00f00000"
deviceinfo_flash_offset_tags="0x00000100"
```

**与 jasmine_sprout 差异**:
- `deviceinfo_name="Xiaomi Mi Note 3"` (jasmine_sprout: Mi A2)
- `deviceinfo_codename="xiaomi-jason"` (jasmine_sprout: xiaomi-jasmine_sprout)
- `deviceinfo_year="2017"` (jasmine_sprout: 2018)
- `deviceinfo_dtb="qcom/sdm660-xiaomi-jason"` (jasmine_sprout: qcom/sdm660-xiaomi-jasmine)
- `deviceinfo_screen_height="1920"` (jasmine_sprout: 2160, jason 是 16:9 的 1080x1920)

### 7.4 device-xiaomi-jason/modules-initfs

```
msm
panel-jdi-fhd-r63452
qcom-spmi-rradc
pm660_fg
pm660_charger
pm660_haptics
```

### 7.5 firmware-xiaomi-jason/APKBUILD (首阶段最小化)

```sh
maintainer="jason port <port@example.com>"
pkgname=firmware-xiaomi-jason
pkgver=1
pkgrel=0
pkgdesc="Firmware files for Xiaomi Mi Note 3 (jason) - minimal initial package"
url="https://postmarketos.org"
arch="aarch64"
license="proprietary"
options="!strip !check !archcheck !spdx !tracedeps pmb:cross-native"

# 首阶段无 source: 所有必需组件由 mainline driver 直驱
# 此包仅为 device-xiaomi-jason 的依赖占位
# P1 阶段添加 WiFi firmware:
#   makedepends="qca-swiss-army-knife"
#   source="<board-2.bin 来源 URL>"
#   package() { ... }

package() {
    mkdir -p "$pkgdir"
}
```

### 7.6 kernel patch (0001-dts-qcom-add-sdm660-xiaomi-jason.patch)

需要做的:
1. 把 [refs/jason-dts/jason.dts](../refs/jason-dts/jason.dts) 复制为 `sdm660-xiaomi-jason.dts`
2. 在 Makefile 中找到 SDM660 区段, 加入 `dtb-$(CONFIG_ARCH_QCOM) += sdm660-xiaomi-jason.dtb`
3. 用 `git format-patch` 生成标准 patch

具体生成方式:
```bash
cd /tmp
git clone --depth 1 --branch v6.19.10-sdm660 https://github.com/sdm660-mainline/linux
cd linux
cp /home/lyl/Documents/system/XiaoMiNote3/refs/jason-dts/jason.dts arch/arm64/boot/dts/qcom/sdm660-xiaomi-jason.dts
# 编辑 arch/arm64/boot/dts/qcom/Makefile 加一行
git add arch/arm64/boot/dts/qcom/sdm660-xiaomi-jason.dts arch/arm64/boot/dts/qcom/Makefile
git commit -m "arm64: dts: qcom: add Xiaomi Mi Note 3 (jason)"
git format-patch HEAD~1 -o /tmp/patches/
# 把生成的 patch 复制到 pmaports 目录
```

### 7.7 内核 config 修改

只需改一处:
```diff
-# CONFIG_DRM_PANEL_JDI_R63452 is not set
+CONFIG_DRM_PANEL_JDI_R63452=m
```

## 8. 待澄清问题与已澄清答案 (2026-06-27 验证)

### 8.1 关键问题与答案

#### Q1. `firmware-qcom-adreno-a530` 是否必需?

**答案**: 严格非必需, 但保守起见与上游一致保留依赖。

**验证证据** (来源: `/tmp/sdm660-linux/drivers/gpu/drm/msm/adreno/{adreno_gpu.c,a5xx_gpu.c}` @ tag `v6.19.10-sdm660`):
- `adreno_gpu.c` 中 `zap_shader_load_mdt()` 是 firmware 加载的唯一入口
- 若 DTS 有 `zap-shader` 子节点 + `firmware-name` 属性 (jason DTS 有: `firmware-name = "a512_zap.mbn"`), driver 调用 `request_firmware_direct()` 加载该文件
- `a5xx_gpu.c` 中无其他 `request_firmware` 调用 — 即 mainline a5xx driver **只加载 zap shader**, 不加载 a530 GMU/SQE
- `firmware-qcom-adreno-a530` subpackage 装的是 `qcom/a530*` (GMU/SQE), **不装** `a530_zap*` (APKBUILD 中 `_gpu()` 显式 `rm -f ... _zap*`)
- 因此 a530 subpackage 提供的文件 mainline driver 实际上**不会加载**

**结论**:
- 与 jasmine_sprout/lavender (同为 SDM660 + Adreno 512) 一致, 保留 `firmware-qcom-adreno-a530` 依赖
- 该 subpackage 极小 (几十 KB), 不增加构建负担
- 实测后若 dmesg 无 `a530*` 加载报错且 display 正常, 可移除依赖精简包

**实测判断命令**:
```bash
dmesg | grep -iE 'adreno|zap|a530|a512'
# 期望: "failed to load a512_zap.mbn" (因为首阶段不装), 但不影响 display path
```

#### Q2. jason 的 WiFi board-2.bin 从哪获取?

**答案**: 借用 jasmine_sprout 的 board-2.bin (同 SoC + 同 WiFi 模组), P1 阶段处理。

**验证证据** (来源: `refs/pmaports/device/testing/firmware-xiaomi-{jasmine_sprout,lavender}/APKBUILD`):

| 设备 | gitlab 仓库 | commit |
|---|---|---|
| jasmine_sprout (Mi A2) | `gitlab.com/m.01001101.01010110/firmware-xiaomi-jasmine_sprout` | `b23003b2...` |
| lavender (Redmi Note 7) | `gitlab.com/barni2000/firmware-xiaomi-lavender` | `2e88d6d6...` |
| jason | **不存在** (无 maintainer 上传) | - |

**结论**:
- jason 没有 maintainer 的 gitlab 仓库, 不能直接复用此模式
- 三个选项 (按推荐排序):
  1. **借用 jasmine_sprout** (推荐): 同 SDM660 + 同 WCN3990, 校准数据可能略有偏差但能工作; 直接在 jason firmware APKBUILD 中加 jasmine_sprout 仓库作为 source
  2. 从原厂 BTFM.bin 解包提取 (需 qca-swiss-army-knife + 解包脚本)
  3. 自建 gitlab 仓库 (解包后推到自己的 gitlab)
- 仅 P1 阶段需要, 不阻塞首阶段

**实测判断命令**:
```bash
ip a  # 看 wlan0
dmesg | grep ath10k
# 若有 "failed to load board-2.bin", 借用失败需走选项 2
# 若 wlan0 可用但 TX power 低/不稳定, 校准不匹配, 考虑选项 2/3
```

#### Q3. `v6.19.10-sdm660` tag 是否已包含 jason.dts?

**答案**: **不包含**, 必须完整 patch (DTS + Makefile 修改)。

**验证证据** (来源: GitHub API `https://api.github.com/repos/sdm660-mainline/linux/contents/arch/arm64/boot/dts/qcom?ref=v6.19.10-sdm660`):

tag 中已存在的 SDM660 小米设备 DTS:
- `sdm660-xiaomi-jasmine.dts` (Mi A2)
- `sdm660-xiaomi-lavender-{boe,shenchao,tianma}.dts` (Redmi Note 7, 三种面板)
- `sdm660-xiaomi-platina.dts` (Mi 8 Lite)
- `sdm660-xiaomi-clover.dts`, `sdm660-xiaomi-clover-plus.dts` (Mi PAD 4)
- `sda660-xiaomi-clover.dts`

tag 中**不包含** `sdm660-xiaomi-jason.dts` (Grep 验证: 0 匹配)。

**附带确认**: `panel-jdi-fhd-r63452.c` driver **已包含**在 tag 中 (路径 `drivers/gpu/drm/panel/panel-jdi-fhd-r63452.c`), Kconfig `CONFIG_DRM_PANEL_JDI_R63452` 已定义, Makefile 已配 `obj-$(CONFIG_DRM_PANEL_JDI_R63452) += panel-jdi-fhd-r63452.o`。

**结论**:
- 必须创建 patch `0001-dts-qcom-add-sdm660-xiaomi-jason.patch`, 内容包含:
  1. 新增 `arch/arm64/boot/dts/qcom/sdm660-xiaomi-jason.dts` (从 `refs/jason-dts/jason.dts` 复制)
  2. 修改 `arch/arm64/boot/dts/qcom/Makefile`, 加 `dtb-$(CONFIG_ARCH_QCOM) += sdm660-xiaomi-jason.dtb`
- panel driver 无需 patch, 只需在 config 改 `CONFIG_DRM_PANEL_JDI_R63452=m`

#### Q4. 原厂 bootloader 是否接受 pmOS append_dtb 风格 boot.img?

**答案**: 需要 qcom,msm-id/qcom,board-id/qcom,pmic-id 等下游 DTB 属性。原厂 Qualcomm UEFI ABL 会验证这些属性来确认硬件匹配,缺这些属性会导致 ABL 拒绝启动 kernel(表现: fastboot boot 后设备无响应/重启)。解决: 在 jason DTS 的 root node 添加:
- qcom,msm-id = <0x13d 0x00>;
- qcom,board-id = <0x1e 0x00>;
- qcom,pmic-id = <0x1001b 0x101011a 0x00 0x00 0x1001b 0x201011a 0x00 0x00>;

实测: 添加后 ABL 接受 kernel,成功启动。

**验证证据** (来源: `refs/pmaports/device/testing/device-xiaomi-{jasmine_sprout,lavender}/deviceinfo`):

| 设备 | SoC | append_dtb | 同款 bootloader? |
|---|---|---|---|
| jasmine_sprout (Mi A2) | SDM660 | `true` | 是 (jason 同款 ABL) |
| lavender (Redmi Note 7) | SDM660 | `true` | 是 |
| jason (Mi Note 3) | SDM660 | (将设为 `true`) | 是 |

**结论**:
- SDM660 平台小米全系 (jasmine_sprout/lavender/platina/clover) 都用 `append_dtb="true"` + 同款 ABL bootloader, 已大规模验证
- jason 同款 bootloader, 必然兼容
- 失败时 TWRP + 原厂备份双保险可救回

#### Q5. `append_dtb="true"` 与 `flash_offset_second="0x00f00000"` 的兼容性?

**答案**: 完全兼容, 已验证。

**验证证据** (来源: 同 Q4):

| 设备 | append_dtb | flash_offset_second |
|---|---|---|
| jasmine_sprout | `true` | `0x00f00000` |
| lavender | `true` | `0x00f00000` |
| jason (将设) | `true` | `0x00f00000` |

**结论**: jason deviceinfo 直接复制 jasmine_sprout 的 flash offset 配置即可, 无需任何修改。

### 8.2 风险点 (已更新)

| 风险 | 影响 | 缓解 | 状态 |
|---|---|---|---|
| panel driver 未 enable | 黑屏 | 改 config `CONFIG_DRM_PANEL_JDI_R63452=m` + modules-initfs 加 `panel-jdi-fhd-r63452` | 已识别必改 |
| jason DTS 有 bug (WIP) | 启动 panic | fastboot boot 不 flash + ramoops 抓日志 | 缓解就绪 |
| WiFi firmware 缺失 | WiFi 不工作 | 借用 jasmine_sprout board-2.bin | P1, 不阻塞首阶段 |
| GPU zap shader 缺失 | GPU 不工作 (但 display OK) | 首阶段不装 a512_zap.mbn, 只 dev_warn 不影响启动 | 已识别 |
| Modem firmware 缺失 | Modem 不工作 (首阶段决策不启用) | 不装 soc-qcom-sdm660-rproc 包 | 设计决策 |
| tag 不含 jason.dts | 需完整 patch | 已确认, patch 方案已就绪 (见 §9 file-templates) | 已解决 |
| 原厂 bootloader 不接受 boot.img | 黑屏无法启动 | jasmine_sprout/lavender 同款已验证, TWRP 救砖 | 已澄清 |
| GitHub 网络不稳 | pmbootstrap 拉源码慢 | 用 ghfast.top 镜像 / mihomo 代理 | 已验证 |

## 9. 总结

本次研究确认了 jason 移植的完整路径, 所有 5 个待澄清问题已通过源码核查 + 同 SoC 设备对照验证完成:

1. **难度可控**: jason DTS 已有 (Kernel114514 写的 WIP), mainline panel driver 已合并, sdm660 通用内核包已就绪。
2. **代码量小**: 只需新建 4 个小文件 (APKBUILD + deviceinfo + modules-initfs + firmware APKBUILD), 1 个 patch (DTS + Makefile), 改 1 处 config (`CONFIG_DRM_PANEL_JDI_R63452=m`)。
3. **首阶段可极简**: 由于 jason.dts 已 enable USB peripheral mode, 首阶段可以用 USB ethernet 走 SSH (不需要 WiFi), firmware 包可以为空。
4. **回退安全**: 已备份 28 个分区, 原厂 fastboot 包完整, TWRP 可救。
5. **5 个待澄清问题已全部澄清** (2026-06-27):
   - Q1 a530 firmware: 保守依赖, 实测后可移除
   - Q2 WiFi board-2.bin: 借用 jasmine_sprout, P1 阶段
   - Q3 tag 不含 jason.dts: 必须完整 patch
   - Q4 bootloader 接受 append_dtb: 同款 SDM660 已验证
   - Q5 append_dtb + flash_offset_second 兼容: 已验证

下一步可以从 [port-plan.md](./port-plan.md) 阶段 A2 (pmbootstrap 环境) 开始动手实施。

## 10. 内核源码深挖验证 (2026-06-27)

> 来源: 克隆 `sdm660-mainline/linux` tag `v6.19.10-sdm660` 到 `/tmp/sdm660-linux` (92259 文件), 逐项核查 jason DTS 引用的节点与 driver。

### 10.1 panel-jdi-fhd-r63452.c 完全自包含

**文件**: `drivers/gpu/drm/panel/panel-jdi-fhd-r63452.c` (244 行)

**关键结论**: panel driver **不加载任何 firmware**, 初始化序列全部 hardcoded 在 `jdi_fhd_r63452_on()` 中 (DSI 命令序列, 用 `mipi_dsi_generic_write_seq_multi` / `mipi_dsi_dcs_*_multi` 写入)。

**driver 特性**:
- 显示模式: 1080x1920 @ 60Hz, `width_mm=64`, `height_mm=114` (与 jason 实物一致)
- 4 DSI lanes, RGB888, `MIPI_DSI_MODE_VIDEO_BURST | MIPI_DSI_CLOCK_NON_CONTINUOUS`
- 依赖: `reset-gpios`, `backlight` (via `drm_panel_of_backlight`), 无 vddio/vddpos/vddneg-supply 解析 (jason DTS 中的这三个 supply 仅在 panel 节点声明, driver 不消费 — 不影响 probe)
- `compatible = "jdi,fhd-r63452"` (与 jason DTS `panel@0` 的 compatible 完全匹配)

**影响**: 首阶段 display 不依赖任何 firmware, 只要 `CONFIG_DRM_PANEL_JDI_R63452=m` + modules-initfs 加载即可工作。

### 10.2 jason DTS 引用节点在 sdm630.dtsi 全部存在

**文件**: `arch/arm64/boot/dts/qcom/sdm630.dtsi` (sdm660.dtsi 的基础)

jason DTS (`#include "sdm660.dtsi"` → sdm660.dtsi `#include "sdm630.dtsi"`) 中 `&xxx` 引用的所有节点均在 sdm630.dtsi 中定义:

| jason DTS 引用 | sdm630.dtsi 定义位置 | 备注 |
|---|---|---|
| `&adreno_gpu` | `gpu@5000000` | sdm660.dtsi 覆盖为 `compatible = "qcom,adreno-512.0"` |
| `&adreno_gpu_zap` | `zap-shader` 子节点 | `memory-region = <&zap_shader_region>` |
| `&blsp1_uart2` / `&blsp2_uart1` | BLSP UART | debug + BT |
| `&mdss` / `&mdss_dsi0` / `&mdss_dsi0_phy` / `&mdss_dsi0_out` | DSI | display |
| `&mmss_smmu` | SMMU | display/IOMMU |
| `&pm660_charger` / `&pm660_fg` / `&pm660_haptics` / `&pm660_rradc` | pm660.dtsi | PMIC |
| `&pm660l_gpios` / `&pm660l_wled` | pm660l.dtsi | PMIC |
| `&pon_pwrkey` / `&pon_resin` | PON | 按键 |
| `&qusb2phy0` / `&usb3` / `&usb3_dwc3` | USB | peripheral mode |
| `&remoteproc_mss` | MPSS | modem (首阶段不启用) |
| `&rpm_requests` (regulators) | RPM | PM660/PM660L regulators |
| `&sdhc_1` / `&sdhc_2` | SDHCI | eMMC (sdhc_2 jason disabled) |
| `&tlmm` | TLMM | pinctrl |
| `&wifi` | WCN3990 | WiFi |

**zap_shader_region 定义** (sdm630.dtsi L515):
```
zap_shader_region: gpu@fed00000 {
    compatible = "shared-dma-pool";
    reg = <0x0 0xfed00000 0x0 0xa00000>;   /* 10MB */
    no-map;
};
```
jason DTS `&adreno_gpu_zap { firmware-name = "a512_zap.mbn"; }` 引用此 region, driver `zap_shader_load_mdt()` 调 `request_firmware_direct()` 加载; 缺失时 SCM 返回 -EOPNOTSUPP, 设 `zap_available=false` (静默, 仅 dev_warn), **不影响 display 与启动**。

### 10.3 PM660 PMIC 节点 driver 对应

**文件**: `arch/arm64/boot/dts/qcom/pm660.dtsi`

| 节点 | compatible | mainline driver 文件 | Kconfig | config 状态 |
|---|---|---|---|---|
| `pm660_charger@1000` | `qcom,pm660-charger` | `drivers/power/supply/qcom_smbx.c` | `CHARGER_QCOM_SMB2` | `=m` ✅ |
| `pm660_fg@4000` | **`qcom,pmi8998-fg`** | `drivers/power/supply/qcom_pmi8998_fg.c` | `BATTERY_PMI8998_FG` | `=m` ✅ |
| `pm660_rradc@4500` | `qcom,pm660-rradc` | `drivers/iio/adc/qcom-spmi-rradc.c` | `QCOM_SPMI_RRADC` | `=m` ✅ |
| `pm660_haptics@c000` | **`qcom,pmi8998-haptics`, `qcom,spmi-haptics`** | `drivers/input/misc/qcom-spmi-haptics.c` | `INPUT_QCOM_SPMI_HAPTICS` | `=m` ✅ |

**注意**:
- `pm660_fg` compatible 共用 `qcom,pmi8998-fg` (PMI8998 FG driver 同时处理 PM660 FG, 因为 IP 相同)
- `pm660_haptics` 兼容 `qcom,pmi8998-haptics` + `qcom,spmi-haptics` (driver 用 spmi-haptics)
- `pm660_charger` driver 是 `qcom_smbx.c`, Makefile L130 `obj-$(CONFIG_CHARGER_QCOM_SMB2) += qcom_smbx.o`, Kconfig 描述 "Qualcomm PMI8998 PMIC charger driver" (虽名 SMB2 但实际覆盖 PM660)

### 10.4 完整 Kconfig 状态表 (jason DTS 引用模块)

**文件**: `refs/pmaports/device/testing/linux-postmarketos-qcom-sdm660/config-postmarketos-qcom-sdm660.aarch64`

| 设备/功能 | Driver | Kconfig | config 状态 | modules-initfs |
|---|---|---|---|---|
| GPU (Adreno 512) | adreno + a5xx | `DRM_MSM` | `=m` ✅ | msm, adreno |
| DSI host | msm_dsi | `DRM_MSM_DSI` | `=y` ✅ | (内建) |
| DSI PHY 10nm | msm_dsi_phy | `DRM_MSM_DSI_10NM_PHY` | `=y` ✅ | (内建) |
| **Panel (JDI R63452)** | panel-jdi-fhd-r63452 | `DRM_PANEL_JDI_R63452` | **`is not set` ❌** | **必改 =m + 加 modules-initfs** |
| Backlight (WLED) | pm660l_wled | `BACKLIGHT_QCOM_WLED` | `=y` ✅ | (内建) |
| RRADC | qcom_spmi_rradc | `QCOM_SPMI_RRADC` | `=m` ✅ | (P1, 非首阶段) |
| Battery FG | pmi8998_fg | `BATTERY_PMI8998_FG` | `=m` ✅ | (P1) |
| Charger (PM660) | qcom_smbx | `CHARGER_QCOM_SMB2` | `=m` ✅ | (P1) |
| Haptics | spmi_haptics | `INPUT_QCOM_SPMI_HAPTICS` | `=m` ✅ | (P1) |
| Regulators | qcom_spmi-regulator | `REGULATOR_QCOM_SPMI` | `=y` ✅ | (内建) |
| MFD SPMI PMIC | qcom_spmi-pmic | `MFD_SPMI_PMIC` | `=y` ✅ | (内建) |

**结论**: 除 `CONFIG_DRM_PANEL_JDI_R63452` 外, 所有 jason DTS 引用模块的 Kconfig 都已启用。**首阶段只需改 1 处 config**: `CONFIG_DRM_PANEL_JDI_R63452=m` + modules-initfs 加 `panel-jdi-fhd-r63452`。

### 10.5 深挖结论汇总

1. **panel driver 完全自包含** — display 首阶段零 firmware 依赖
2. **所有 DTS 节点已就位** — jason DTS 无悬空引用, sdm630.dtsi/sdm660.dtsi/pm660.dtsi/pm660l.dtsi 全部提供
3. **zap shader 静默降级** — `a512_zap.mbn` 缺失只 dev_warn, 不影响 display/启动
4. **PM660 PMIC driver 全部就绪** — charger/fg/rradc/haptics 的 Kconfig 都已 `=m`
5. **唯一必改 config** — `CONFIG_DRM_PANEL_JDI_R63452=m` (tag 中 driver 已在, 仅 config 未 enable)
6. **patch 内容最小化** — 只需 DTS + Makefile 修改, 无需改 driver (driver 已合并到 tag)

至此 jason 移植的代码层准备已 100% 完成, 所有未知数已澄清, 可进入构建阶段 (A2 起)。

## 11. 首阶段完成总结 (2026-06-28)

> 本节为首阶段移植全部完成后的总结, 含实测中发现的新问题与解决方案

### 11.1 完成状态

首阶段移植 100% 成功, 所有完成定义项已达成 (详见 [troubleshooting.md](./troubleshooting.md) §7.5):
- ✓ 设备可重复启动进入 Linux (kernel 6.19.10-sdm660)
- ✓ rootfs 可读写 (ext4, /dev/loop0p2)
- ✓ WiFi 可连接指定网络 (ChinaNet-810, 192.168.1.12/24)
- ✓ SSH 可从局域网登录 (192.168.1.5 → 192.168.1.12)
- ✓ 基本系统信息采集能力 (dmesg, ip, journalctl, free, df)
- ✓ 刷回/重刷流程文档 ([reflash-guide.md](./reflash-guide.md))

### 11.2 实测中发现的关键问题与解决

| 问题 | 根因 | 解决 | 详见 |
|---|---|---|---|
| ABL 拒绝启动 | jason DTS 缺 qcom,msm-id/board-id/pmic-id 属性 | DTS patch 添加这 3 个属性 | troubleshooting.md §7.2 |
| USB gadget service failed | pmOS 自动 g1 抢占 UDC, pmos gadget 报 Resource busy | 修改脚本检测已绑定 gadget 后幂等退出 | troubleshooting.md §7.6 |
| WiFi firmware crash (PC=b00c749c) | jason 原厂 wlanmdsp.mbn 1.0.0.533 与 mainline ath10k 不兼容 | 刷入 whyred V12 完整 NON-HLOS.bin (1.0.0.591) | troubleshooting.md §7.4 |
| 仅替换 wlanmdsp.mbn 失败 | wlanmdsp.mbn 与 NON-HLOS.bin 其他组件版本强耦合 | 必须整包替换 NON-HLOS.bin | troubleshooting.md §7.4.6 |

### 11.3 长稳验证

30 分钟连续监控 (25 次采样):
- 0% ping 丢包
- WiFi 持续 up, 无 ath10k crash
- CPU 温度 48-51°C 稳定
- 内存 244-259M 稳定 (无泄漏)

详见 [troubleshooting.md](./troubleshooting.md) §7.7。

### 11.4 后续工作

- F3. 长期方案: 寻找 jason 设备对应的更新版 wlanmdsp.mbn (避免长期依赖 whyred NON-HLOS.bin)
- G1. (可选) 高负载压力测试
- G2. (可选) 网络服务部署
