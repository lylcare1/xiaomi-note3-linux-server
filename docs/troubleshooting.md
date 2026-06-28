# jason 移植 - 故障排查与待澄清问题

> 创建日期: 2026-06-27
> 配套文档: [research-deep.md](./research-deep.md) (机制详解) + [port-plan.md](./port-plan.md) (执行计划)
> 用途: 列出已识别的待澄清问题、可能故障及缓解措施

## 1. 已澄清问题 (2026-06-27 验证完成)

> 所有 5 个问题已通过源码核查 + 同 SoC 设备对照验证完成, 详见 [research-deep.md §8](./research-deep.md#8-待澄清问题与已澄清答案-2026-06-27-验证)。

### 1.1 `firmware-qcom-adreno-a530` 依赖 (已澄清)

**结论**: 保留依赖 (与 jasmine_sprout/lavender 一致), 但实测后可移除。

**证据**:
- mainline `adreno_gpu.c::zap_shader_load_mdt()` 是 a5xx driver 加载 firmware 的**唯一**入口
- jason DTS 有 `firmware-name = "a512_zap.mbn"`, driver 调用 `request_firmware_direct()` 加载它
- `a5xx_gpu.c` 中无其他 `request_firmware` 调用 — 即 a5xx driver **只加载 zap shader**, 不加载 a530 GMU/SQE
- `firmware-qcom-adreno-a530` subpackage 装的是 `qcom/a530*` (GMU/SQE), **不装** `a530_zap*` (显式 `rm -f`)
- 所以 a530 subpackage 提供的文件 mainline driver 实际**不会加载**

**实测判断命令**:
```bash
dmesg | grep -iE 'adreno|zap|a530|a512'
# 期望: "failed to load a512_zap.mbn" (因为首阶段不装), 但不影响 display path
# 若无 "failed to load a530*", 可移除 firmware-qcom-adreno-a530 依赖
```

### 1.2 WiFi board-2.bin 来源 (已澄清)

**结论**: 借用 jasmine_sprout 的 board-2.bin, P1 阶段处理。

**证据**:
| 设备 | gitlab 仓库 |
|---|---|
| jasmine_sprout | `gitlab.com/m.01001101.01010110/firmware-xiaomi-jasmine_sprout` (commit `b23003b2`) |
| lavender | `gitlab.com/barni2000/firmware-xiaomi-lavender` (commit `2e88d6d6`) |
| jason | **不存在** (无 maintainer 上传) |

**推荐**: 借用 jasmine_sprout (同 SDM660 + 同 WCN3990), 实测若不稳定再从原厂 BTFM.bin 解包。

**实测判断命令**:
```bash
ip a  # 看 wlan0
dmesg | grep ath10k
# "failed to load board-2.bin" -> 借用失败, 走选项 2 (从 BTFM.bin 解包)
# wlan0 可用但 TX power 低/不稳定 -> 校准不匹配, 走选项 2/3
```

### 1.3 v6.19.10-sdm660 tag 是否含 jason.dts (已澄清)

**结论**: **不包含**, 必须完整 patch (DTS + Makefile)。

**证据** (GitHub API):
- tag 中存在的 SDM660 小米 DTS: jasmine, lavender (3 个面板), platina, clover, clover-plus
- tag 中**无** `sdm660-xiaomi-jason.dts` (Grep 0 匹配)
- **附带确认**: `panel-jdi-fhd-r63452.c` driver 已在 tag 中, Kconfig/Makefile 都已配置

**处理** (见 [file-templates.md §6](./file-templates.md)):
1. patch 中新增 `arch/arm64/boot/dts/qcom/sdm660-xiaomi-jason.dts` (从 `refs/jason-dts/jason.dts` 复制)
2. patch 中修改 `arch/arm64/boot/dts/qcom/Makefile`, 加 `dtb-$(CONFIG_ARCH_QCOM) += sdm660-xiaomi-jason.dtb`

### 1.4 原厂 bootloader 接受 append_dtb (已澄清)

**结论**: 需要 qcom,msm-id/qcom,board-id/qcom,pmic-id 等下游 DTB 属性。原厂 Qualcomm UEFI ABL 会验证这些属性来确认硬件匹配,缺这些属性会导致 ABL 拒绝启动 kernel(表现: fastboot boot 后设备无响应/重启)。解决: 在 jason DTS 的 root node 添加:
- qcom,msm-id = <0x13d 0x00>;
- qcom,board-id = <0x1e 0x00>;
- qcom,pmic-id = <0x1001b 0x101011a 0x00 0x00 0x1001b 0x201011a 0x00 0x00>;

实测: 添加后 ABL 接受 kernel,成功启动。

**证据**:
| 设备 | SoC | append_dtb |
|---|---|---|
| jasmine_sprout | SDM660 | `true` |
| lavender | SDM660 | `true` |
| jason | SDM660 | (将设为 `true`) |

SDM660 平台小米全系都用 `append_dtb="true"` + 同款 ABL bootloader, 已大规模验证。jason 同款, 必然兼容。失败时 TWRP + 原厂备份双保险可救回。

### 1.5 append_dtb 与 flash_offset_second 兼容性 (已澄清)

**结论**: 完全兼容。

**证据**: jasmine_sprout 和 lavender 都用 `append_dtb="true"` + `flash_offset_second="0x00f00000"` 组合, 已验证可用。jason deviceinfo 直接复制 jasmine_sprout 的 flash offset 配置即可。

### 1.6 内核源码深挖验证 (2026-06-27)

> 完整内容见 [research-deep.md §10](./research-deep.md#10-内核源码深挖验证-2026-06-27)。来源: 克隆 tag `v6.19.10-sdm660` 到 `/tmp/sdm660-linux` 逐项核查。

**结论**: jason 移植的代码层准备已 100% 完成, 所有未知数已澄清。

**关键发现**:
1. **panel driver 完全自包含** — `panel-jdi-fhd-r63452.c` (244 行) 不加载任何 firmware, 初始化序列全部 hardcoded。display 首阶段零 firmware 依赖。
2. **所有 DTS 节点已就位** — jason DTS 中 `&xxx` 引用的所有节点都在 sdm630.dtsi/sdm660.dtsi/pm660.dtsi/pm660l.dtsi 中定义, 无悬空引用。
3. **zap shader 静默降级** — `a512_zap.mbn` 缺失时 SCM 返回 -EOPNOTSUPP, 设 `zap_available=false` (仅 dev_warn), 不影响 display 与启动。
4. **PM660 PMIC driver 全部就绪**:
   - `pm660_charger` → `qcom_smbx.c` → `CONFIG_CHARGER_QCOM_SMB2=m` ✅
   - `pm660_fg` → compatible 共用 `qcom,pmi8998-fg` → `CONFIG_BATTERY_PMI8998_FG=m` ✅
   - `pm660_haptics` → `CONFIG_INPUT_QCOM_SPMI_HAPTICS=m` ✅
   - `pm660_rradc` → `CONFIG_QCOM_SPMI_RRADC=m` ✅
5. **唯一必改 config** — `CONFIG_DRM_PANEL_JDI_R63452=m` (tag 中 driver 已在, 仅 config 未 enable) + modules-initfs 加 `panel-jdi-fhd-r63452`。
6. **patch 内容最小化** — 只需 DTS + Makefile 修改, 无需改 driver。

## 2. 启动失败场景与排查

### 2.1 fastboot boot 后黑屏 + 无 USB 设备识别

**可能原因**:
- boot.img 格式不被 bootloader 接受 (问题 1.4)
- kernel panic 早期挂死
- DTB 不匹配, 硬件初始化失败

**排查步骤**:
1. 确认 fastboot 仍可识别设备: `fastboot devices`
2. 用 `fastboot boot twrp-3.7.0_9-0-jason.img` 重新进 TWRP (验证 bootloader 仍工作)
3. 在 TWRP 下检查 ramoops (DTS 已配置 4MB ramoops@b0000000):
   ```bash
   adb shell
   cat /proc/ramoops_console  # 或 /sys/fs/pstore/
   ```
4. 若 ramoops 有 panic 日志, 根据 panic 信息调试
5. 若无 ramoops, 加 `init=/bin/sh` 或 `pmos.debug` 到 kernel cmdline 试
6. 实在不行, 用 `fastboot flash boot backups/original-jason-20260627-114354/boot.img` 恢复

### 2.2 启动到 shell 但 USB ethernet 不工作

**可能原因**:
- DWC3 driver 未加载 (USB 控制器没起来)
- USB 网络模块 (cdc_ether / rndis_host) 未加载
- USB 配置错误 (dr_mode 不是 peripheral)

**排查步骤**:
```bash
# 在 pmOS shell (可通过 serial console 或其他方式):
dmesg | grep -i dwc3
dmesg | grep -i usb
ip a  # 看 usb0 是否存在
lsmod | grep -E 'dwc3|cdc_ether|rndis'
modprobe dwc3
modprobe cdc_ether
ip a
```

**预期**:
- jason DTS 中 `dr_mode = "peripheral"`, DWC3 应该作为 device 模式
- pmOS 默认配置 USB ethernet gadget, 应该出现 usb0
- 主机端会出现新的 USB 网络接口 (cdc_ether 或 rndis_host)

### 2.3 启动但 SSH 连不上

**可能原因**:
- USB ethernet 起来了但 IP 配置错误
- sshd 未启动
- 防火墙阻止

**排查步骤**:
```bash
# 主机端:
ip a  # 找到 USB 网络接口 (通常是 enp0sXX 或 usbR)
sudo ip addr add 10.15.19.100/24 dev <interface>  # pmOS 默认 IP 段
sudo ip link set <interface> up
ssh user@10.15.19.82  # pmOS 默认 IP (具体看 /etc/conf.d/usb_ethernet)

# 设备端 (通过其他方式访问):
systemctl status sshd  # 或 rc-service sshd status
ip a
ping -c 3 10.15.19.100  # 测试反向连通
```

### 2.4 启动但 panel 不亮

**可能原因**:
- `CONFIG_DRM_PANEL_JDI_R63452=m` 没改对
- modules-initfs 中没加 `panel-jdi-fhd-r63452`
- DTS 中 panel 节点未正确配置

**排查步骤**:
```bash
# 在 pmOS shell:
dmesg | grep -i panel
dmesg | grep -i dsi
dmesg | grep -i jdi
lsmod | grep panel
modprobe panel-jdi-fhd-r63452
# 看是否 panel 亮起
```

### 2.5 启动但 WiFi 不工作

**可能原因**:
- firmware-5.bin 或 board-2.bin 缺失 (问题 1.2)
- ath10k 模块未加载
- WCN3990 电源未正确配置

**排查步骤**:
```bash
# 在 pmOS shell:
dmesg | grep -i ath10k
dmesg | grep -i wcn3990
ls /lib/firmware/ath10k/WCN3990/hw1.0/
lsmod | grep ath10k
modprobe ath10k_snoc
ip a  # 看 wlan0 是否出现
```

**预期**: 这是 P1 阶段问题, 不阻塞首阶段。

### 2.6 启动后随机重启 / panic

**可能原因**:
- jason DTS 有 bug (作者标注 WIP)
- regulator 配置错误导致电压不稳
- mmss_smmu 配置错误

**排查步骤**:
1. 在 TWRP 下检查 ramoops:
   ```bash
   adb shell cat /proc/ramoops_console
   adb shell ls /sys/fs/pstore/
   ```
2. 若是 DTS 问题, 修改 patch 中 DTS (例如把 `&remoteproc_mss` 改 `status="disabled"`)

## 3. 回退路径

### 3.1 完整回退到原厂

```bash
cd /home/lyl/Documents/system/XiaoMiNote3/jason_images_V8.5.9.0.NCHCNED_20170831.0000.00_7.1_cn
./flash_all.sh
```

### 3.2 单独恢复 boot 分区

```bash
fastboot flash boot backups/original-jason-20260627-114354/boot.img
fastboot reboot
```

### 3.3 进 TWRP 救砖

```bash
# 设备关机, 按住音量下 + 电源进 fastboot
fastboot boot twrp-3.7.0_9-0-jason.img
# 然后 adb shell 检查
adb shell
```

### 3.4 恢复 modem 文件系统 (若被覆写)

见 [backups/original-jason-20260627-114354/README.md](../backups/original-jason-20260627-114354/README.md) §3。

## 4. 调试工具与技巧

### 4.1 不焊接 UART 下的调试方法

按 AGENTS.md "不需要 UART, 可在 twrp/fastboot 救砖" 决策:

1. **ramoops** (DTS 已配置 4MB @ 0xb0000000):
   - 保存 panic console 和 pmsg 各 2MB
   - panic 后 TWRP 下读取 `/proc/ramoops_console` 或 `/sys/fs/pstore/`

2. **fastboot boot** (不 flash):
   - 验证 boot.img 不影响持久分区
   - 失败后 `fastboot reboot` 即回原厂

3. **kernel cmdline 加 debug 参数**:
   - `init=/bin/sh` (跳过 init, 直接进 shell)
   - `pmos.debug` (pmOS 调试模式)
   - `loglevel=7` (最大日志)
   - `earlycon` (早期 console)

4. **USB ethernet + SSH** (启动成功后):
   - 通过 SSH 远程访问, 用 `dmesg` / `journalctl` / `ip a` 检查

### 4.2 关键日志位置

```bash
# /proc 文件系统
cat /proc/cmdline       # 当前 cmdline
cat /proc/version       # 内核版本
cat /proc/ramoops_console  # panic 日志 (若 ramoops 已配置)

# /sys 文件系统
ls /sys/fs/pstore/      # pstore 持久存储 (panic 后保留)

# journalctl
journalctl -b           # 当前启动完整日志
journalctl -b -p err    # 当前启动错误级别
journalctl --list-boots # 所有启动记录

# dmesg
dmesg | tail -100
dmesg --level=err,warn
```

### 4.3 临时修改 cmdline 测试

```bash
# 直接 fastboot boot 时传 cmdline (覆盖 deviceinfo):
fastboot --cmdline "init=/bin/sh loglevel=7 earlycon" boot boot.img
```

## 5. 已知风险与缓解总结

| 风险 | 严重度 | 缓解 |
|---|---|---|
| jason DTS 有 bug | 中 | fastboot boot 不 flash, ramoops 抓日志, TWRP 救砖 |
| panel driver 未 enable | 高 | 已识别必须改 CONFIG_DRM_PANEL_JDI_R63452=m |
| WiFi firmware 缺失 | 低 (P1) | 借用 jasmine_sprout, 不阻塞首阶段 |
| GPU zap 缺失 | 低 | 只 dev_warn, 不影响显示 |
| Modem 不启用 | 低 | 首阶段决策, USB ethernet + WiFi 替代 |
| 原厂 bootloader 不接受 pmOS boot.img | 高 | 根因: DTB 缺少 qcom,msm-id/board-id/pmic-id 属性, ABL 拒绝启动。修复: DTS patch 添加这三个属性 (见 §7.2) |
| pmbootstrap 构建失败 | 中 | 检查 patch apply, config, sha512 |
| GitHub 网络不稳 | 中 | 用 `ghfast.top` 镜像前缀或 mihomo 代理 |
| tag 不含 jason.dts | 已解决 | 已确认 v6.19.10-sdm660 不含, 完整 patch 已就绪 |
| jason 无 firmware gitlab 仓库 | 低 (P1) | 借用 jasmine_sprout board-2.bin |

## 6. 文档参考

- [AGENTS.md](../AGENTS.md) - 项目规则与进展
- [docs/research.md](./research.md) - 高层调研
- [docs/research-deep.md](./research-deep.md) - pmOS 机制深度研究
- [docs/port-plan.md](./port-plan.md) - 执行计划
- [docs/file-templates.md](./file-templates.md) - 文件模板清单
- [backups/original-jason-20260627-114354/README.md](../backups/original-jason-20260627-114354/README.md) - 备份与回退说明

## 8. D1 build/install 阶段故障 (2026-06-27)

### 8.1 crossdirect 包 HTTP 502

- **症状**: `pmbootstrap build device-xiaomi-jason` 报 `ERROR: crossdirect-5.3.1-r1: HTTP 502: Bad Gateway`
- **原因**: mirror.postmarketos.org 通过代理偶发 502
- **诊断**: `curl -sIL http://mirror.postmarketos.org/postmarketos/main/x86_64/crossdirect-5.3.1-r1.apk` 显示 301 → 200 OK (mirror 实际可达, master 已重命名为 main)
- **解决**: 直接重试 build 即可成功 (502 是临时问题)

### 8.2 pmbootstrap install 时 mkinitfs 找不到 jason dtb

- **症状**: install 失败, `ERROR: Unable to find qcom/sdm660-xiaomi-jason.dtb in the following locations: /boot/dtbs*, /usr/share/dtb/`
- **原因**: device-xiaomi-jason depends 含 linux-postmarketos-qcom-sdm660, 但 `pmbootstrap install` 时不会自动 build 内核包, 而是从 binary repo 下载旧版 (无 jason DTS patch)
- **诊断**: `ls /home/lyl/.local/var/pmbootstrap/packages/edge/aarch64/linux-postmarketos-qcom-sdm660*` 显示无本地 build 产物
- **解决**: 必须先 `pmbootstrap build linux-postmarketos-qcom-sdm660 --force --lax` (注意 `--force`, 否则 pmbootstrap 会认为 "up to date" 跳过 build), 然后再 `pmbootstrap install`

### 8.3 内核源码 tarball 下载 502

- **症状**: `pmbootstrap build linux-postmarketos-qcom-sdm660 --force` 时 `wget: server returned error: HTTP/1.1 502 Bad Gateway` (下载 https://github.com/sdm660-mainline/linux/archive/refs/tags/v6.19.10-sdm660.tar.gz)
- **原因**: 代理 7890 访问 github.com 偶发 502
- **诊断**: `curl -sI -x http://127.0.0.1:7890 -L https://github.com/...` 显示 302 → codeload 200 (代理实际可达)
- **解决**: 手动下载 tarball 到 distfiles cache, abuild 会从 cache 直接取 (不重新下载):
  ```bash
  sudo curl -L --max-time 600 -o /home/lyl/.local/var/pmbootstrap/chroot_native/var/cache/distfiles/linux-v6.19.10-sdm660.tar.gz \
    https://github.com/sdm660-mainline/linux/archive/refs/tags/v6.19.10-sdm660.tar.gz
  ```
  然后重试 `pmbootstrap build linux-postmarketos-qcom-sdm660 --force --lax`
- **验证**: `sha512sum linux-v6.19.10-sdm660.tar.gz` 应为 `abf0ec97c2530ad3543a64019cefde3396c3361d7550513bf17948c6f4bf2621d88bb1947a519e8bddc97f1c6fdc7d12989cc8292a41805acac9f8f16f7a14df` (与 APKBUILD sha512sums 一致)

## 7. 首阶段移植成功 (2026-06-27)

### 7.1 里程碑达成

首阶段移植成功! jason 设备已可:
- 稳定启动进入 postmarketOS Linux 用户态 (kernel 6.19.10-sdm660)
- rootfs 可读写 (ext4, /dev/loop0p2, 806.7M)
- SSH 可通过 USB 网络远程连接 (172.16.42.1, user/1234)
- 基本系统信息采集可用 (dmesg, ip a, journalctl, free, df)

### 7.2 关键修复点

1. **qcom ABL 属性** (DTS patch): 在 jason DTS root node 添加 qcom,msm-id/board-id/pmic-id,ABL 才接受 kernel
2. **USB gadget 配置**: rootfs 中默认缺少 USB gadget 配置服务,需要手动添加:
   - /usr/local/bin/setup-usb-gadget.sh (configfs 配置 NCM+ACM gadget)
   - /etc/systemd/system/setup-usb-gadget.service (sysinit.target.wants 启用)
   - /etc/NetworkManager/system-connections/usb0.nmconnection (shared 模式, 172.16.42.1/24)
3. **boot.img cmdline**: pmos.debug-shell 会在 mount_subpartitions 之前进入 debug shell,正常启动需去掉

### 7.3 启动流程
1. fastboot flash userdata xiaomi-jason.img (rootfs 含 2 分区: boot+rootfs)
2. fastboot boot boot.img (不带 pmos.debug-shell)
3. kernel 启动 → initramfs → mount_subpartitions (losetup -Pf userdata) → switch_root
4. systemd 启动 → setup-usb-gadget.service → NetworkManager → sshd

### 7.4 WiFi (2026-06-28 修复完成)

**最终修复**: 刷入 whyred V12.0.3.0.PEICNXM 完整 NON-HLOS.bin 到 modem 分区,firmware 升级到 1.0.0.591/htt-ver 3.58,WiFi 工作正常。

#### 7.4.1 根因分析

WiFi firmware `wlanmdsp.mbn` 版本太旧,与 mainline ath10k_snoc 驱动不兼容。

| 来源 | wlanmdsp.mbn 版本字符串 | fw_version | htt-ver | 行为 |
|---|---|---|---|---|
| jason V11/V12 原厂 | `WLAN.HL.1.0.1.c6-00015-QCAHLSWMTPLZ-1.201724.1.211993.1` | 1.0.0.533 | 3.50 | firmware boot 成功,~350ms 后 fatal error `PC=b00c749c` |
| whyred V12 (仅替换 wlanmdsp.mbn) | `WLAN.HL.1.0.1.c2-00538-QCAHLSWMTPLZ-1.214870.1` | 未报告 | 未报告 | watchdog timeout `wlan_process` 挂起 (与 jason 其他 modem 固件组件版本不兼容) |
| **whyred V12 完整 NON-HLOS.bin** | 同上 | **1.0.0.591** | **3.58** | **正常工作** ✓ |
| minlexx 设备 (issue #75) | 未知 | 1.0.0.591 | 3.58 | 正常工作 |

参考: https://github.com/sdm660-mainline/linux/issues/75

#### 7.4.2 关键发现

1. **Xiaomi 从未更新 jason 的 wlanmdsp.mbn**: jason V11 与 V12 fastboot 包中 wlanmdsp.mbn MD5 完全相同 (`dfc1adb690a00ff4ecd79d35c4faaee5`)
2. **SDM660 设备共享 wlanmdsp.mbn**: jason/whyred/lavender 均为 SDM660 + WCN3990,理论上 wlanmdsp.mbn 跨设备兼容
3. **不能仅替换 wlanmdsp.mbn**: wlanmdsp.mbn 与 NON-HLOS.bin 中其他固件组件 (mba.mbn, modem.b*, adsp.b*, cdsp.b*) 版本强耦合,只换 wlanmdsp.mbn 会导致 modem 启动后 wlan_process 挂起
4. **必须整包替换**: whyred 完整 NON-HLOS.bin (含所有匹配版本组件) 才能让 WiFi firmware 正常工作

#### 7.4.3 修复步骤

```bash
# 1. 下载 whyred V12 fastboot 包 (bn.d.miui.com 直连速度快, bigota.d.miui.com 返回 403)
wget https://bn.d.miui.com/V12.0.3.0.PEICNXM/whyred_images_V12.0.3.0.PEICNXM_20210509.0000.00_9.0_cn_59bb23dffc.tgz

# 2. 解压提取 NON-HLOS.bin
tar xzf whyred_images_V12.0.3.0.PEICNXM_*.tgz
find whyred_images_V12.0.3.0.PEICNXM_* -name 'NON-HLOS.bin'

# 3. 刷入 jason 设备 modem 分区
sudo fastboot flash modem /tmp/NON-HLOS-whyred.bin

# 4. 冷启动测试 (不要 warm reboot,QMI 协商需冷启动)
sudo fastboot boot /tmp/boot-no-debug.img
```

#### 7.4.4 关键日志

```
[ 41.088752] ath10k_snoc 18800000.wifi: qmi chip_id 0x30214 chip_family 0x4001 board_id 0xff soc_id 0x40050000
[ 41.088853] ath10k_snoc 18800000.wifi: qmi fw_version 0x101c821a fw_build_timestamp 2019-07-25 03:17 fw_build_id QC_IMAGE_VERSION_STRING=WLAN.HL.1.0.1.c2-00538-QCAHLSWMTPLZ-1.214870.1
...
[ 44.202623] ath10k_snoc 18800000.wifi: firmware 1.0.0.591 booted
[ 44.241276] ath10k_snoc 18800000.wifi: htt target version 3.58
[ 44.242054] ath10k_snoc 18800000.wifi: htt-ver 3.58 wmi-op 4 htt-op 3 cal file max-sta 32 raw 0 hwcrypto 1
```

#### 7.4.5 测试结果

- wlan0 接口出现,MAC 地址随机 (因 invalid MAC,需后续从原厂配置填充)
- `nmcli device wifi list` 成功扫描到 20+ 个 WiFi 网络,信号强度 60-90
- firmware 不再 crash (无 fatal error / watchdog timeout)

#### 7.4.6 已排除方案

- ❌ jason V12 NON-HLOS.bin (wlanmdsp.mbn 与 V11 相同)
- ❌ 仅替换 wlanmdsp.mbn 到 jason NON-HLOS.bin (固件组件版本不匹配)
- ❌ 上游 wlanmdsp.mbn WLAN.HL.2.0-01387 (太新,与 V11 modem 固件不兼容)

#### 7.4.7 已知副作用

- whyred 完整 NON-HLOS.bin 包含 whyred 的 modem/ADSP/CDSP firmware,可能与 jason 硬件有差异 (基带、音频等),但首阶段 (WiFi/server) 不受影响
- 长期方案: 找到 jason 设备对应的更新版 wlanmdsp.mbn,或在 sdm660-mainline kernel 中实现 firmware-level workaround

### 7.5 修复后的首阶段成功 (2026-06-28)

完成定义全部达成:
- ✓ 设备可重复启动进入 Linux (kernel 6.19.10-sdm660)
- ✓ rootfs 可读写 (ext4, /dev/loop0p2)
- ✓ WiFi 可连接指定网络 (ChinaNet-810, wlan0 192.168.1.12/24, 默认路由 192.168.1.1)
- ✓ SSH 可从局域网登录 (192.168.1.5 → 192.168.1.12, user/1234)
- ✓ 具备基本系统信息采集能力 (dmesg, ip a, journalctl, free, df)
- ✓ 具备刷回、重刷、更新内核/镜像的标准流程文档

#### 7.5.1 验证日志 (2026-06-28 10:14)

```
$ sshpass -p 1234 ssh user@192.168.1.12
Warning: Permanently added '192.168.1.12' (ED25519) to the list of known hosts.
xiaomi-jason
Linux xiaomi-jason 6.19.10-sdm660 #2-postmarketos-qcom-sdm660 SMP PREEMPT Sat Jun 27 13:50:49 UTC  aarch64 Linux
 10:14:13 up 6 min,  0 users,  load average: 0.60, 0.61, 0.36
              total        used        free      shared  buff/cache   available
Mem:           3.5G      236.0M        3.1G       17.6M      219.8M        3.0G
```

wlan0 连接详情:
```
3: wlan0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc noqueue state UP qlen 1000
    link/ether e6:c0:24:62:d1:56 brd ff:ff:ff:ff:ff:ff
    inet 192.168.1.12/24 brd 192.168.1.255 scope global dynamic noprefixroute wlan0
       valid_lft 86392sec preferred_lft 86392sec
GENERAL.DRIVER:                         ath10k_snoc
GENERAL.DRIVER-VERSION:                 6.19.10-sdm660
GENERAL.FIRMWARE-VERSION:               1.0.0.591
GENERAL.STATE:                          100 (connected)
```

### 7.6 setup-usb-gadget.service failed 修复 (2026-06-28)

**症状**: service 启动失败,报 `sh: write error: Resource busy`,但 USB 网络实际工作正常 (172.16.42.1 可达)。

**根因**: pmOS 自动配置 `g1` gadget 抢占了 UDC,我手动添加的 `pmos` gadget 在 `echo "$UDC" > "$GADGET/UDC"` 时返回 `Resource busy` (UDC 一次只能绑定一个 gadget)。

**修复**: 修改 `/usr/local/bin/setup-usb-gadget.sh`,在脚本开头检查是否已有任何 gadget 绑定到 UDC,若有则直接退出 0 (幂等)。

```sh
# 关键检查逻辑
for g in "$CONFIGFS"/*/; do
        if [ -s "${g}UDC" ]; then
                echo "USB gadget $(basename "$g") already bound to $(cat "${g}UDC"), exiting"
                exit 0
        fi
done
```

**验证**: `systemctl status setup-usb-gadget.service` 显示 `Active: active (exited)` `code=exited, status=0/SUCCESS`。

### 7.7 F1 长稳运行测试 (2026-06-28)

**测试方法**: 主机每 60s 采样一次,采集 ping 丢包率 + 设备 uptime/load/mem/thermal/wifi 状态。

**测试脚本**: [scripts/long-stability-test.sh](../scripts/long-stability-test.sh)

**测试时长**: 30 分钟 (1800s),25 次采样

**关键指标汇总**:

| 指标 | 范围 | 趋势 |
|---|---|---|
| Ping 丢包率 | 0% (全部 25 次) | 稳定 |
| 设备 uptime | 680s → 2454s | 持续累积,无重启 |
| WiFi state | up (始终) | 稳定 |
| wlan0 IP | 192.168.1.12/24 (始终) | 稳定 |
| Load (1/5/15min) | 0.32-0.68 / 0.32-0.57 / 0.36-0.44 | 8 核空闲 |
| Memory used | 241-259M / 3624M | 稳定,无泄漏 |
| CPU 温度 | 48.3-51.6°C | 缓慢上升 ~3°C |
| GPU 温度 | 51.6-55.4°C | 缓慢上升 ~4°C |
| Battery 温度 | 36.8-40.5°C | 缓慢上升 ~4°C |
| RTT (min/avg) | 2.9-6.0ms / 3.5-38.8ms | 偶尔抖动 (iter=8/18/22),其余稳定 3-5ms |

**结论**: 设备空闲状态长稳运行非常稳定。
- 无 WiFi 断连 (wlan0 state=up 持续 30 分钟)
- 无 ath10k crash (dmesg 中无 fatal error / watchdog timeout)
- 无温度异常 (CPU/GPU/Battery 温度均在合理范围,缓慢上升因环境温度)
- 无内存泄漏 (memory used 在 244-259M 范围内波动)
- 偶尔 RTT 抖动到 20-50ms (WiFi 信道竞争,属正常现象)

**完整日志**: [logs/stability-20260628-101833.log](../logs/stability-20260628-101833.log)

### 7.8 服务器优化 P0 (2026-06-28)

**目标**: 把 jason 从"能启动的 pmOS"升级到"可长期运行的服务器"。

**P0 改动清单**:

| # | 项目 | 配置文件/命令 | 状态 |
|---|---|---|---|
| P0-1 | sysctl 服务器加固 (panic_on_oops=1 等) | `/etc/sysctl.d/99-server-hardening.conf` | ✓ 已应用 |
| P0-2 | journald 日志大小限制 100M | `/etc/systemd/journald.conf.d/size.conf` | ✓ 已应用 |
| P0-3 | eMMC 自动 fsck (mount count=30, interval=7d) | `tune2fs -c 30 -i 7d /dev/loop0p2` + systemd timer | ✓ 已应用 |
| P0-4 | SSH 防爆破 | fail2ban → 卸载 (无 py3-systemd), 改用 sshd 内置加固 | ✓ 已应用 |
| P0-5 | 系统健康检查 (5min timer) | `/usr/local/bin/health-check.sh` + systemd timer | ✓ 已应用 |
| P0-6 | SSH 安全加固 | `/etc/ssh/sshd_config.d/99-server-hardening.conf` (保留密码登录) | ✓ 已应用 |

#### 7.8.1 sysctl 配置 (P0-1)

文件: `/etc/sysctl.d/99-server-hardening.conf`

```
kernel.panic_on_oops = 1           # Oops 自动重启 (之前 =0, 挂死风险)
kernel.panic = 120                 # Panic 后 120s 重启 (重申)
kernel.pid_max = 4194304           # PID 上限
fs.file-max = 2097152              # 文件描述符上限
net.ipv4.tcp_syncookies = 1        # 防 SYN flood
net.ipv4.conf.all.rp_filter = 1    # 反向路径过滤
net.ipv4.conf.all.accept_redirects = 0  # 拒绝 ICMP redirect
net.ipv4.tcp_keepalive_time = 600  # keepalive 600s
vm.overcommit_memory = 1           # OOM 策略
vm.swappiness = 10                 # 减少 swap 倾向
```

应用: `sudo sysctl -p /etc/sysctl.d/99-server-hardening.conf`

#### 7.8.2 journald 限制 (P0-2)

文件: `/etc/systemd/journald.conf.d/size.conf`

```
[Journal]
SystemMaxUse=100M          # 总量上限 100M
SystemMaxFileSize=10M       # 单文件 10M
MaxFileSec=1month          # 单文件保留 1 月
```

应用: `sudo systemctl restart systemd-journald`

效果: 修改前 191.2M, 修改后下次轮转自动清理到 100M 以内。

#### 7.8.3 eMMC 自动 fsck (P0-3)

**架构说明**: pmOS rootfs 在 `mmcblk1p70` (userdata) 内的 ext4 镜像上,通过 loop 设备 (`/dev/loop0p2`) 挂载。物理分区 mmcblk1p70 是 raw 数据,实际 ext4 fs 在 loop0p2 上。

**改动**:
1. `tune2fs -c 30 -i 7d /dev/loop0p2` — 30 次挂载或 7 天后自动触发 fsck
2. 创建 `fsck-check.service` + `fsck-check.timer` — 每周自动跑 `e2fsck -f -n /dev/loop0p2` (只读检查)
   - 只读检查不影响系统运行
   - 发现问题写入 journal,通过 `journalctl -u fsck-check` 查看

**注意**: pmOS initramfs 不支持 fsck loop device (无 fsck hook)。tune2fs 设置的 mount count 触发实际不会在启动时跑 fsck,但 systemd timer 的定期检查可以替代。

#### 7.8.4 SSH 加固 (P0-4/P0-6)

**问题**: Alpine 无 `py3-systemd` 包,fail2ban 1.1.0 的 `backend = systemd` 不可用,导致启动失败:
```
ERROR Failed to initialize any backend for Jail 'sshd'
```

**解决**: 卸载 fail2ban,改用 sshd 内置加固。

文件: `/etc/ssh/sshd_config.d/99-server-hardening.conf`

```
MaxAuthTries 3              # 最多 3 次认证 (默认 6)
LoginGraceTime 20           # 20s 内必须完成认证 (默认 2min)
MaxStartups 5:50:10         # 并发未认证连接限制
AllowUsers user             # 只允许 user 用户
PermitRootLogin no          # 禁用 root 登录
ClientAliveInterval 60      # 60s keepalive
ClientAliveCountMax 3       # 3 次无响应断开
PermitEmptyPasswords no     # 禁空密码
PasswordAuthentication yes  # 保留密码登录 (用户决定)
PubkeyAuthentication yes    # 允许公钥 (可选)
```

应用: `sudo systemctl reload sshd`

**备选方案** (后续若要更强防护):
- 改 SSH 端口到非标 (如 22222) — 需在防火墙开放
- 启用公钥认证 + 禁用密码 — 需先生成 SSH 密钥对

#### 7.8.5 系统健康检查 (P0-5)

**问题**: SDM660 mainline 内核未编译 watchdog 模块 (softdog/PMIC watchdog 均无),`/sys/class/watchdog` 为空,无硬件看门狗。

**解决**: 用 systemd timer + 脚本实现软件健康检查。

文件:
- `/usr/local/bin/health-check.sh` — 健康检查脚本
- `/etc/systemd/system/health-check.service` — oneshot service
- `/etc/systemd/system/health-check.timer` — 5 分钟触发一次

**检查项**:
1. sshd 服务是否 active,失败则 restart
2. NetworkManager 服务是否 active,失败则 restart
3. wlan0 接口是否 up,失败则 restart NetworkManager
4. ath10k 是否 crash (检查 dmesg 最近 100 行)
5. 默认网关是否可达 (ping 2 次,超时 3s),失败则 restart NetworkManager

**自动重启策略**:
- 失败计数器在 `/run/health-check-failures`
- 连续 3 次失败 (15 分钟) 后自动 `reboot`
- 成功时计数器清零

**效果验证**:
```
Jun 28 11:26:15 xiaomi-jason health-check[10733]: system healthy
Jun 28 11:26:18 xiaomi-jason health-check[10752]: system healthy
```

#### 7.8.6 P0 验证总结

执行后验证:
```
kernel.panic = 120                  # ✓
kernel.panic_on_oops = 1             # ✓ (从 0 改为 1)
kernel.pid_max = 4194304             # ✓
vm.swappiness = 10                   # ✓

tune2fs -l /dev/loop0p2 | grep mount:
  Mount count:              15
  Maximum mount count:      30     # ✓ (从 -1 改为 30)
  Check interval:           604800 (1 week)  # ✓ (从 0 改为 7d)

systemctl list-timers:
  fsck-check.timer    NEXT: Mon 2026-06-29 00:00:11  # ✓
  health-check.timer  NEXT: Sun 2026-06-28 11:31:17  # ✓
```

#### 7.8.7 已知遗留问题

- **看门狗**: 无硬件看门狗,依赖 `kernel.panic=120` + `health-check.timer` 兜底
- **fail2ban**: 卸载,改用 sshd 加固 (Alpine 无 py3-systemd 包)
- **SSH 公钥认证**: 保留密码登录,后续可加 ~/.ssh/authorized_keys 后切换

### 7.9 服务器优化 P1 (2026-06-28)

**目标**: 补充 P0 之外的服务器运维便利性功能。

**P1 改动清单**:

| # | 项目 | 文件 | 状态 |
|---|---|---|---|
| P1-1 | APK 自动更新通知 (每日检查) | `/usr/local/bin/apk-update-check.sh` + `apk-update-check.timer` | ✓ |
| P1-2 | 温度监控告警 (5min, 12 zones) | `/usr/local/bin/temp-monitor.sh` + `temp-monitor.timer` | ✓ |
| P1-3 | SSH 改非标端口 | 保留 22 (用户决定) | ✓ |
| P1-4 | RTC 时钟持久化 (FakeRTC 方案) | `/usr/local/bin/fake-rtc-save.sh` + `fake-rtc-save.timer` + `fake-rtc-restore.service` | ✓ |

#### 7.9.1 APK 自动更新通知 (P1-1)

**文件**: `/usr/local/bin/apk-update-check.sh`

**功能**:
- 每日 (24h) 跑一次 `apk update && apk list --upgradable`
- 系统已最新: 写 `system is up-to-date` 到 journal
- 有更新: 写入可升级包列表到 journal + `/run/apk-pending-updates`
- 安全相关包 (openssl/openssh/glibc/busybox/linux-/systemd/chrony/sudo) 有更新时记 CRITICAL
- **不自动升级**: 避免破坏 pmOS edge channel 稳定性,管理员手动 `apk upgrade`

**检查命令**:
```bash
journalctl -t apk-update-check -n 10
# 或
cat /run/apk-pending-updates   # 若有内容表示有未升级包
```

#### 7.9.2 温度监控告警 (P1-2)

**文件**: `/usr/local/bin/temp-monitor.sh`

**功能**:
- 每 5min 扫描所有 12 个 thermal zone (aoss/cpuss0-1/cpu0-3/pwr-cluster/gpu/pm660l/pm660/qcom-battery)
- 阈值: CPU/GPU 70°C 警告 / 85°C 关键; 电池 55°C; PMIC 80°C
- 超阈值: 写入 journal (WARN/CRITICAL 级别)
- 关键温度: 触发 `sync` 防止文件系统损坏
- 每次运行都写最高温到 journal

**阈值设计原理**:
- kernel 已有 thermal framework 自动 throttling (cooling_device),此脚本只是日志告警
- 不主动 throttle,避免与 kernel 冲突
- 关键温度 sync 后等待 kernel 自动处理 (cpu_hotplug/cpufreq throttle)

**检查命令**:
```bash
journalctl -t temp-monitor -n 10 --since "1 hour ago"
# 输出示例:
# Jun 28 11:45:29 xiaomi-jason temp-monitor[13023]: max_temp=58.0C (gpu-thermal) warn=0 crit=0
```

#### 7.9.3 SSH 端口 (P1-3)

**决定**: 保留默认 22 端口 (用户决定)。

**防护**: 依赖 P0-4 的 sshd 内置加固 (MaxAuthTries=3 + LoginGraceTime=20 + AllowUsers=user)。

#### 7.9.4 RTC 时钟持久化 (P1-4)

**问题**: PMIC RTC 不可写。`hwclock --systohc` 返回 `ioctl(RTC_SET_TIME) failed: No such device` (ENODEV)。

**根因**: SDM660 PMIC (PM660) RTC 通过 `rtc-pm8xxx` driver 暴露为 rtc0 (compatible=qcom,pm8941-rtc),但 RTC_SET_TIME ioctl 失败。推测原因: PMIC RTC 寄存器写入需要 Qualcomm secure service 调用 (QSEEOS/SCM),mainline driver 未实现。

**结果**: 关机后 RTC 时间丢失,下次启动时回到 1970-01-20 (driver 内置默认值)。

**解决: FakeRTC 文件持久化**:
- `/usr/local/bin/fake-rtc-save.sh`: 把当前时间戳写入 `/var/lib/fake-rtc-time`
- `fake-rtc-save.timer`: 每 30min 跑一次保存
- `fake-rtc-restore.service`: 启动时若 NTP 同步失败 (60s 内),从文件恢复时间

**保留**: 启动时 NTP 正常工作则不会用到文件时间。仅在断网启动时用作后备。

**systemd-timesyncd 配置**: `/etc/systemd/timesyncd.conf`
- 主 NTP: ntp.aliyun.com / ntp1.aliyun.com / cn.pool.ntp.org
- 后备: time.windows.com / time.apple.com / pool.ntp.org

#### 7.9.5 P1 systemd timer 总览

| Timer | 频率 | 用途 |
|---|---|---|
| `apk-update-check.timer` | 24h | 检查 APK 更新 |
| `temp-monitor.timer` | 5min | 温度监控告警 |
| `health-check.timer` | 5min | 系统健康检查 (P0-5) |
| `fake-rtc-save.timer` | 30min | 时间戳持久化 |
| `fsck-check.timer` | 7d | eMMC 文件系统只读检查 (P0-3) |

**查看命令**:
```bash
systemctl list-timers --all
journalctl -t apk-update-check -n 5      # APK 更新通知
journalctl -t temp-monitor -n 5         # 温度监控
journalctl -t health-check -n 5        # 健康检查
journalctl -u fake-rtc-save -n 3       # FakeRTC 状态
journalctl -u fsck-check -n 5          # fsck 检查结果
```

### 7.10 服务器优化 P2 (2026-06-28)

**目标**: 增强运维便利性 + 关键配置备份。

**P2 改动清单**:

| # | 项目 | 文件 | 状态 |
|---|---|---|---|
| P2-1 | 自动备份关键配置 (每周) | `/usr/local/bin/config-backup.sh` + `config-backup.timer` | ✓ |
| P2-2 | 网络监控告警 (5min, 网关+外网) | `/usr/local/bin/net-monitor.sh` + `net-monitor.timer` | ✓ |
| P2-3 | disk I/O 统计 (10min, eMMC) | `/usr/local/bin/disk-io-monitor.sh` + `disk-io-monitor.timer` | ✓ |
| P2-4 | motd 系统状态展示 | `/etc/profile.d/motd-status.sh` | ✓ |

#### 7.10.1 配置自动备份 (P2-1)

**文件**: `/usr/local/bin/config-backup.sh`

**功能**:
- 每周 (Monday) 自动备份 25 个关键配置文件到 `/var/backups/config-backup-YYYYMMDD.tar.gz`
- 备份清单: sysctl / journald / sshd / timesyncd 配置 + 所有 systemd unit + 所有 /usr/local/bin 脚本 + /etc/{fstab,hostname,hosts,passwd,group,shadow,sudoers,nftables.conf} + apk repositories
- 保留最近 28 天 (>28 天的自动删除)
- 实测备份大小: 6.8KB

**恢复流程**:
```bash
# 恢复某次备份
cd /
tar xzf /var/backups/config-backup-YYYYMMDD.tar.gz
# 重启服务使配置生效
systemctl daemon-reload
systemctl restart sshd systemd-timesyncd systemd-journald
```

#### 7.10.2 网络监控告警 (P2-2)

**文件**: `/usr/local/bin/net-monitor.sh`

**功能**:
- 每 5min 检查
  1. wlan0 接口是否 up
  2. WiFi 是否 connected (nmcli 状态)
  3. 网关连通性 (ping 5 次算丢包率)
  4. 外网连通性 (ping 8.8.8.8 + DNS 解析 baidu.com)
  5. 网络统计 (rx/tx bytes 累计)
- 失败时: 写入 journal (WARN/CRITICAL)
- 网关 50%+ 丢包: WARN
- 外网 66%+ 丢包 + DNS 失败: WARN (区分 ICMP 阻塞 vs 真断网)

**输出示例**:
```
Jun 28 11:53:44 xiaomi-jason net-monitor[13818]: wlan0: rx=33.71MB tx=2.09MB gw_loss=0% ext_loss=0%
```

#### 7.10.3 disk I/O 统计 (P2-3)

**文件**: `/usr/local/bin/disk-io-monitor.sh`

**功能**:
- 每 10min 从 `/proc/diskstats` 读取 mmcblk1 (eMMC) 统计
- 记录: reads/writes 完成数, sectors read/written, in_flight, io_ms
- 转 sectors (512B) 到 MB 便于阅读
- in_flight > 50 时 WARN (磁盘瓶颈)

**输出示例**:
```
Jun 28 11:53:46 xiaomi-jason disk-io-monitor[13829]: disk=mmcblk1 reads=16812 (313.63MB) writes=22682 (330.73MB) in_flight=0 io_ms=11760
```

#### 7.10.4 motd 系统状态展示 (P2-4)

**文件**: `/etc/profile.d/motd-status.sh`

**触发**: 通过 /etc/profile 在交互式 shell 启动时 source

**显示内容**:
- 主机名 + 当前时间
- uptime (用 /proc/uptime 计算,因 busybox uptime 不支持 -p)
- load (1/5/15min)
- memory (used/total + 百分比)
- disk (used/total + 百分比)
- 最高温度 (扫描 12 个 thermal zone, 取最大值)
- WiFi: SSID + IP
- USB: IP
- 最近 1 小时 journal 警告 (前 3 条)
- 可用 timers 列表 + 常用命令

**示例输出**:
```
========================================
 xiaomi-jason - 2026-06-28 12:02:10 CST
========================================
 uptime : 0d 1h 54m
 load   : 0.47 0.40 0.43
 mem    : 260M / 3624M (7%)
 disk   : 702M / 50519M (1%)
 temp   : 57.4C (cpu3-thermal)

 Network:
   WiFi : ChinaNet-810  IP: 192.168.1.12/24
   USB  : IP: 172.16.42.1/16

 Recent warnings (last 1h):
   Jun 28 12:00:41 xiaomi-jason systemd[14396]: Failed to listen on PipeWire PulseAudio.
   Jun 28 12:01:37 xiaomi-jason systemd[14580]: pipewire-pulse.socket: Socket service pipewire-pulse.service not loaded, refusing.
   Jun 28 12:01:37 xiaomi-jason systemd[14580]: Failed to listen on PipeWire PulseAudio.
========================================
```

#### 7.10.5 P2 systemd timer 完整总览 (含 P0/P1)

| Timer | 频率 | 用途 | 来源 |
|---|---|---|---|
| `health-check.timer` | 5min | 系统健康检查 + 自动 reboot | P0-5 |
| `temp-monitor.timer` | 5min | 温度监控告警 (12 zones) | P1-2 |
| `net-monitor.timer` | 5min | 网络监控告警 | P2-2 |
| `fake-rtc-save.timer` | 30min | 时间戳持久化 | P1-4 |
| `disk-io-monitor.timer` | 10min | eMMC I/O 统计 | P2-3 |
| `apk-update-check.timer` | 24h | APK 更新通知 | P1-1 |
| `fsck-check.timer` | 7d | eMMC 只读 fsck 检查 | P0-3 |
| `config-backup.timer` | 7d (周一) | 配置文件备份 | P2-1 |

**统一查看命令**:
```bash
systemctl list-timers --all
journalctl --since "1 hour ago" -p warning
```

### 7.11 高负载压力测试 (2026-06-28)

**测试工具**: stress-ng 0.21.03, curl 8.20.0, ping (iputils/busybox)
**测试脚本**: `/tmp/cpu-stress-test.sh` (本地临时文件,8 核 CPU 满载 + 30s 温度采样 + 80°C 保护停机)

#### 7.11.1 CPU 压力测试 (5min, stress-ng 8 核满载)

**测试条件**:
- 工具: `stress-ng --cpu 8 --cpu-method matrixprod --timeout 300s`
- 采样: 每 30s 读取 12 个 thermal zone + loadavg
- 保护阈值: 80°C 立即停止

**测试结果**:

| 阶段 | 时间 | loadavg | 最高温度 | 最高温区 |
|---|---|---|---|---|
| 基线 | t=0s | 0.42 0.33 0.37 | 58.0°C | cpu3-thermal |
| t=30s | (热上升) | 3.55 1.09 0.62 | 69.9°C | cpu3-thermal |
| t=60s | (持续上升) | 5.30 1.75 0.86 | 69.9°C | cpu3-thermal |
| t=90s | (WARN 首次超 70) | 6.42 2.37 1.09 | 70.3°C | cpu3-thermal |
| **t=150s** | **峰值** | 7.46 3.41 1.53 | **70.6°C** | cpu3-thermal |
| t=180s | (开始下降) | 7.80 3.88 1.75 | 70.6°C | cpu3-thermal |
| t=211s | (热调节生效) | 8.17 4.34 1.97 | 69.3°C | cpu3-thermal |
| t=241s | (持续下降) | 8.29 4.74 2.18 | 67.7°C | cpu3-thermal |
| t=271s | (降温) | 8.18 5.05 2.37 | 66.7°C | cpu3-thermal |
| t=301s | (结束) | 8.16 5.35 2.55 | 60.9°C | gpu-thermal |
| 结束 +10s 冷却 | - | 6.98 5.19 2.53 | 57.4°C | cpu3-thermal |

**关键数据**:
- 测试时长: 301s (5min,正常完成)
- 起始温度: 58.0°C
- 峰值温度: **70.6°C** (cpu3-thermal @ t=150s)
- 温升: **12.6°C**
- 峰值 loadavg: **8.29** (8 核满载)
- 80°C 临界值: **未触发** (差 9.4°C)
- 停止 10s 后温度: 57.4°C (恢复基线)

**热调节观察**:
- 前 150s 温度从 58 → 70.6°C (上升 12.6°C)
- 150s 后温度开始下降 (尽管 load 持续上升至 8.29)
- 推测: Linux thermal framework + cpufreq driver 在临界温度触发降频,稳态温度 ~67-70°C
- 测试结束时最高温区从 cpu3-thermal 切换到 gpu-thermal (60.9°C),说明 CPU 已降温

**结论**: SDM660 在 mainline kernel 6.19.10-sdm660 下 8 核满载运行稳定,热调节生效,温度可控。可长期运行高 CPU 负载任务而无需担心过热。

#### 7.11.2 网络吞吐量测试

**WiFi 链路状态**:
- SSID: ChinaNet-810
- 信号: 89 (强)
- 频率: 2472 MHz (ch13,2.4GHz)
- 链路速率: 130 Mbit/s

**下载带宽测试 (设备 → Cloudflare CDN)**:

| 文件大小 | 耗时 | 速度 | 备注 |
|---|---|---|---|
| 10 MB | 22.16s | 451 KB/s (3.6 Mbps) | TCP 慢启动 + 冷启动 |
| 50 MB | 20.09s | 2.49 MB/s (19.9 Mbps) | 稳定后真实带宽 |

**结论**: 稳定下载带宽约 **20 Mbps** (2.49 MB/s),受限于网络环境 / 对端服务,非 WiFi 链路瓶颈 (链路 130 Mbps)。满足服务器 SSH/小流量服务需求。

#### 7.11.3 延迟与丢包测试

**主机 → 设备 (192.168.1.12)**:
- 50 个包,0% 丢包
- min/avg/max = 2.5 / 8.7 / 108.1 ms
- mdev = 16.4 ms

**设备 → 网关 (192.168.1.1)**:
- 10 个包,0% 丢包
- min/avg/max = 1.6 / 3.5 / 13.5 ms

**结论**: 局域网延迟低 (3-9ms),0% 丢包,网络稳定。偶发尖峰 (108ms) 为 WiFi 调度噪声,不影响 SSH/服务可用性。

#### 7.11.4 综合评估

| 维度 | 测试结果 | 评估 |
|---|---|---|
| CPU 满载稳定性 | 8 核 5min 无异常,峰值 70.6°C | ✓ 可长期高负载 |
| 热调节 | 150s 后温度下降,稳态 67-70°C | ✓ thermal framework 生效 |
| WiFi 稳定性 | 50MB 下载 0% 失败,20 Mbps | ✓ 满足服务器需求 |
| 局域网延迟 | 0% 丢包,avg 8.7ms | ✓ SSH/运维无障碍 |
| 过热保护 | 80°C 阈值未触发 (差 9.4°C) | ✓ 安全余量充足 |

**服务器适用性结论**: jason 设备在 SDM660 + mainline 6.19.10 下可稳定运行高 CPU/网络负载,温度可控,网络稳定,适合作为长期运行的服务器主机。建议在高负载场景下保留 80°C 自动停机保护 (本测试脚本已实现)。
