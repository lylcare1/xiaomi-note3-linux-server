# jason pmaports patches

Xiaomi Mi Note 3 (jason) 移植到 postmarketOS 所需的全部源码改动,
从 pmbootstrap 工作区 `~/.local/var/pmbootstrap/cache_git/pmaports/` 抽取固化而来。

这些改动在 pmbootstrap 工作区里是未提交的本地修改, 如果执行 `pmbootstrap zap`
或重装 pmbootstrap 会丢失。本目录 + `scripts/apply-jason-patches.sh` 提供
一键重新应用的能力。

## 上游基线

| 项 | 值 |
|---|---|
| 仓库 | https://gitlab.postmarketos.org/postmarketOS/pmaports.git |
| commit hash | `34a631a01eb65fad2cc244a0b0916ae51a256f48` |
| commit 日期 | 2026-06-26 23:42:11 +0000 |
| commit 主题 | ci: Tag x86 and x86_64 jobs with architecture tags |
| 浅克隆 | 是 (pmbootstrap 默认 shallow clone, `git log --oneline` 仅 1 条) |

## kernel tag

`v6.19.10-sdm660` (来自 sdm660-mainline 社区 fork: https://github.com/sdm660-mainline/linux)

由 `linux-postmarketos-qcom-sdm660/APKBUILD` 中的字段确定:

```
pkgver=6.19.10
_tag="v$pkgver-sdm660"      # => v6.19.10-sdm660
source="linux-$_tag.tar.gz::https://github.com/sdm660-mainline/linux/archive/refs/tags/$_tag.tar.gz ..."
```

## 改动清单

### 1. `device-xiaomi-jason/` (新建, 整目录)

pmOS 设备包, 定义 jason 设备元信息与 initramfs 模块。

| 文件 | 用途 |
|---|---|
| `APKBUILD` | 设备包构建脚本, 依赖 `linux-postmarketos-qcom-sdm660`, `firmware-xiaomi-jason`, `soc-qcom-sdm660`, `soc-qcom-sdm660-rproc`, `firmware-qcom-adreno-a530`, `mkbootimg`, `msm-firmware-loader`, `postmarketos-base` |
| `deviceinfo` | 设备信息: codename=xiaomi-jason, dtb=qcom/sdm660-xiaomi-jason, append_dtb=true, flash_method=fastboot, pagesize=4096, flash offset (base=0x0, kernel=0x8000, ramdisk=0x1000000, second=0xf00000, tags=0x100) |
| `kernel-cmdline.conf` | 内核 cmdline 调试参数: loglevel=8, ignore_loglevel, earlycon, console=ttyMSM0,115200 |
| `modules-initfs` | initramfs 加载模块: msm, panel-jdi-fhd-r63452, qcom-spmi-rradc, pmi8998_fg, qcom_smbx, qcom-spmi-haptics |

### 2. `firmware-xiaomi-jason/` (新建, 整目录)

WiFi (WCN3990 / ath10k_snoc) 固件包。

| 文件 | 用途 |
|---|---|
| `APKBUILD` | 构建脚本: 用 `qca-swiss-army-knife` 的 `ath10k-fwencoder` 生成 firmware-5.bin (WCN3990 通用 flags), 安装到 `/lib/firmware/ath10k/WCN3990/hw1.0/firmware-5.bin`; 同时安装 `board-data.bin` 为 `board.bin` (从设备原厂 modem 分区提取的 bdwlan.bin) |
| `board-data.bin` | 19152 字节, jason 设备原厂 WiFi board data (二进制) |

### 3. `linux-postmarketos-qcom-sdm660/` (3 patches + 覆盖 APKBUILD + 覆盖 config)

#### 3.1 `0001-dts-qcom-add-sdm660-xiaomi-jason.patch`

新增 jason 设备树 (548 行 DTS)。

- **Subject**: `arm64: dts: qcom: add Xiaomi Mi Note 3 (jason)`
- **作者**: jason port (原始 DTS by Kernel114514)
- **改动**:
  - `arch/arm64/boot/dts/qcom/Makefile`: 注册 `sdm660-xiaomi-jason.dtb`
  - `arch/arm64/boot/dts/qcom/sdm660-xiaomi-jason.dts` (新文件): 完整设备树, 基于 sdm660.dtsi / pm660.dtsi / pm660l.dtsi
- **关键内容**: ABL 所需 `qcom,msm-id/board-id/pmic-id` 属性, ramoops 节点, UART debug 串口, 触摸屏, 按键, 振动马达, LED, 电池, 充电等
- **用途**: jason 设备能被 ABL 接受启动, 并正确描述硬件供驱动绑定

#### 3.2 `0002-ath10k-wcn3990-skip-psmode.patch`

WCN3990 WiFi 固件崩溃 workaround。

- **改动文件**: `drivers/net/wireless/ath/ath10k/mac.c`
- **内容**: 在 `ath10k_mac_vif_setup_ps()` 开头, 如果是 WCN3990 (`QCA_REV_WCN3990(ar)`) 直接返回 0, 跳过 PS Mode 设置命令
- **根因**: WCN3990 firmware 在收到 set PS Mode 命令后会 fatal error `PC=b00c749c`, 导致 WiFi 启动 ~350ms 后崩溃
- **代价**: 禁用 WiFi 省电 (powersave), 对服务器场景可接受
- **参考**: https://github.com/sdm660-mainline/linux/issues/75

#### 3.3 `0003-cpufreq-hw-sdm660.patch`

启用 SDM660 cpufreq-hw (OSM-HW v1) 驱动与 OPP 表。

- **Subject**: `arm64: dts: qcom: sdm660: enable cpufreq-hw (OSM-HW v1)`
- **改动文件**: `arch/arm64/boot/dts/qcom/sdm660.dtsi`
- **内容**:
  - 新增 `cpufreq@17d43000` 节点 (compatible `qcom,sdm660-cpufreq-hw`, 两个 freq domain)
  - 新增 cluster0 OPP 表 (Silver A53, max 1766 MHz, 10 个频点)
  - 新增 cluster1 OPP 表 (Gold A73, max 2208 MHz, 12 个频点)
  - 8 个 CPU 节点添加 `qcom,freq-domain` 引用与 `operating-points-v2`
- **效果**: `qcom-cpufreq-hw` 驱动注册 cpufreq policy, 8 个 Kryo 260 核心可动态调频
- **测试**: 在 jason 上验证, fw 1.0.0.591, 压力测试稳态 67-70°C

#### 3.4 `APKBUILD` (覆盖上游版本)

相对上游的修改:

- `pkgrel`: `0` -> `2` (bump, 因为新增了 patches)
- `source=`: 追加 3 个 patch 文件
- `package()`: 移除 `vmlinuz.efi` 安装步骤 (jason 用 fastboot, 不需要 EFI)
- `sha512sums=`: 更新为新的 kernel tarball / config / 3 patches 的校验值

#### 3.5 `config-postmarketos-qcom-sdm660.aarch64` (覆盖上游版本)

kernel defconfig 的本地修改版, 相对上游主要启用 jason 所需的驱动配置
(详细 diff 见 pmaports `git diff`):
- `CONFIG_DRM_PANEL_JDI_R63452=m` (jason 屏幕面板, 必改项)
- 其他 jason 相关 config 调整

## 应用方法

### 一键应用

```sh
# 推荐: 直接执行 (走 #!/bin/sh shebang, 不会被 shell 函数包装器拦截)
./scripts/apply-jason-patches.sh

# 或指定 pmaports 目录
./scripts/apply-jason-patches.sh /path/to/pmaports

# 在标准终端也可以用 (注意: 某些 IDE 如 Trae 会用函数包装 sh/cp/rm,
# 此时需用上面的直接执行方式或显式 /bin/sh)
/bin/sh scripts/apply-jason-patches.sh
```

默认应用到 pmbootstrap 工作区的 pmaports
(`~/.local/var/pmbootstrap/cache_git/pmaports`)。

脚本幂等, 可重复运行 (已存在的目录会被覆盖)。

### 应用后构建

```sh
pmbootstrap checksum device-xiaomi-jason firmware-xiaomi-jason linux-postmarketos-qcom-sdm660
pmbootstrap build device-xiaomi-jason
pmbootstrap build firmware-xiaomi-jason
pmbootstrap build linux-postmarketos-qcom-sdm660
pmbootstrap install
```

## 目录结构

```
refs/jason-pmaports-patches/
├── README.md                                        # 本文件
├── device-xiaomi-jason/
│   ├── APKBUILD
│   ├── deviceinfo
│   ├── kernel-cmdline.conf
│   └── modules-initfs
├── firmware-xiaomi-jason/
│   ├── APKBUILD
│   └── board-data.bin                               # 19152 bytes, 原厂 WiFi board data
└── linux-postmarketos-qcom-sdm660/
    ├── 0001-dts-qcom-add-sdm660-xiaomi-jason.patch  # jason DTS
    ├── 0002-ath10k-wcn3990-skip-psmode.patch         # WiFi PS mode workaround
    ├── 0003-cpufreq-hw-sdm660.patch                  # cpufreq-hw + OPP tables
    ├── APKBUILD                                     # 覆盖上游 (pkgrel=2, +3 patches, -vmlinuz.efi)
    └── config-postmarketos-qcom-sdm660.aarch64       # 覆盖上游 (启用 jason 相关 config)
```

## 相关文档

- `docs/research-deep.md` §10: 内核源码深挖验证 (panel driver, DTS 节点引用, zap shader)
- `docs/troubleshooting.md` §7.4: WiFi firmware 修复 (whyred NON-HLOS.bin 替换)
- `docs/reflash-guide.md`: 完整刷回原厂 / 重刷 pmOS 流程
- `refs/jason-dts/jason.dts`: 原始 DTS 参考文件 (作者 Kernel114514)
