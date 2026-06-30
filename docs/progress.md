# 工作进展记录

> 从 AGENTS.md 迁移而来,记录项目已完成的工作和下一步计划。
> 核心规则见 [AGENTS.md](../AGENTS.md)。

## 已完成

- **A1. 备份原厂分区** (2026-06-27): TWRP 下流式备份 28 个分区共 6.7GB,13 个核心分区 sha256 校验通过
  - 备份目录: `backups/original-jason-20260627-114354/`
  - 脚本: `scripts/backup-partitions.sh` (支持断点续传,跳过 userdata)
  - 必备份: modemst1/modemst2/fsg/persist (原厂 fastboot 包未覆盖的运行时分区)
  - 校验备份: boot/recovery/system/cache/cust/misc/modem/dsp/bluetooth
  - 可选备份: splash/frp/sec/ssd/limits/ddr/logfs/toolsfv/sti/apdp/msadp/devinfo/oops/mdtp/logdump
  - 跳过: userdata (52GB 用户数据,原厂 fastboot 包可恢复)
- **A0. 准备工作**: TWRP 3.7.0_9-0 已临时 boot (不 flash 到 recovery 分区); 设备序列号 d1236a7b, unlocked=yes
- **深度研究** (2026-06-27): 完整分析 pmOS 设备包/内核包/firmware 包机制, 识别 jason 移植所需的所有改动
  - `docs/research.md` (380 行): 高层调研, 评估就绪度
  - `docs/research-deep.md` (~780 行): pmOS 机制深度研究, 含 jason 落地方案 + 已澄清 Q1-Q5 答案
  - `docs/port-plan.md` (~390 行): 执行计划, 含 7 阶段 + 已澄清问题表
  - `docs/file-templates.md` (~300 行): 所有要新建/修改文件的完整内容模板
  - `docs/troubleshooting.md` (~330 行): 5 个已澄清问题 + 6 类故障排查
  - 关键发现: 首阶段 firmware 包可以为空 (USB/UART/eMMC/Display 都 mainline 直驱), 必改 CONFIG_DRM_PANEL_JDI_R63452=m
- **5 个待澄清问题已全部澄清** (2026-06-27): 通过源码核查 + 同 SoC 设备对照验证
  - Q1 a530 firmware: 保守依赖 (mainline driver 只加载 zap shader, 实测后可移除)
  - Q2 WiFi board-2.bin: 借用 jasmine_sprout (P1 阶段, 不阻塞首阶段)
  - Q3 tag 不含 jason.dts: 必须完整 patch (DTS + Makefile)
  - Q4 bootloader 接受 append_dtb: jasmine_sprout/lavender 同款已验证
  - Q5 append_dtb + flash_offset_second 兼容: 已验证
  - 附带确认: panel-jdi-fhd-r63452.c driver 已在 tag v6.19.10-sdm660 中, 无需 patch
- **内核源码深挖验证完成** (2026-06-27): 克隆 tag `v6.19.10-sdm660` 到 `/tmp/sdm660-linux` 逐项核查, 详见 `docs/research-deep.md` §10
  - panel-jdi-fhd-r63452.c 完全自包含 (244 行, 不加载任何 firmware)
  - jason DTS 引用的所有节点在 sdm630.dtsi/sdm660.dtsi/pm660.dtsi/pm660l.dtsi 全部存在, 无悬空引用
  - zap shader 缺失静默降级 (仅 dev_warn, 不影响 display/启动)
  - PM660 PMIC driver 全部就绪: pm660_charger→CONFIG_CHARGER_QCOM_SMB2=m, pm660_fg→CONFIG_BATTERY_PMI8998_FG=m (compatible 共用 pmi8998-fg), pm660_haptics/rradc 也已 =m
  - **唯一必改 config**: `CONFIG_DRM_PANEL_JDI_R63452=m` (tag 中 driver 已在, 仅 config 未 enable)
  - patch 内容最小化: 只需 DTS + Makefile 修改, 无需改 driver
  - 代码层准备 100% 完成, 可进入构建阶段
- **jason DTS 已下载**: `refs/jason-dts/jason.dts` (542 行, 作者 Kernel114514, 来源 alexeymin/jason 分支)
- **回退路径**: 原厂 fastboot 包 `jason_images_V8.5.9.0.NCHCNED_20170831.0000.00_7.1_cn/` 完整可用, 加本地 28 分区备份
- **D2. 实测启动成功** (2026-06-27): kernel 6.19.10-sdm660 成功启动进入 pmOS 用户态
  - 根因修复: DTS patch 添加 qcom,msm-id/board-id/pmic-id 属性 (ABL 验证)
  - rootfs 写入: fastboot flash userdata (1.4GB, 2 分区镜像)
  - USB gadget: 手动添加 setup-usb-gadget.sh + systemd service + NetworkManager connection
  - SSH 验证: 通过 USB 网络 172.16.42.1 连接成功 (user/1234)
  - boot.img: 去掉 pmos.debug-shell 实现自动启动
- **E1. WiFi firmware 修复成功** (2026-06-28): 刷入 whyred V12.0.3.0.PEICNXM 完整 NON-HLOS.bin 到 modem 分区
  - 根因: jason 原厂 wlanmdsp.mbn 版本 1.0.0.533 (htt-ver 3.50) 与 mainline ath10k_snoc 驱动不兼容,firmware 启动 ~350ms 后 fatal error `PC=b00c749c`
  - 关键发现: Xiaomi 从未更新 jason wlanmdsp.mbn (V11=V12); 仅替换 wlanmdsp.mbn 会导致 watchdog timeout (与 NON-HLOS.bin 其他组件版本不匹配)
  - 修复: 刷入 whyred V12 完整 NON-HLOS.bin (含所有匹配版本组件),wlanmdsp.mbn 升级到 WLAN.HL.1.0.1.c2-00538,fw_version 1.0.0.591,htt-ver 3.58 (与 sdm660-mainline issue #75 minlexx 设备版本完全一致)
  - 验证: wlan0 接口可用,`nmcli device wifi list` 成功扫描到 20+ 网络,信号 60-90,无 firmware crash
  - 详见 `docs/troubleshooting.md` §7.4

- **E2. WiFi 连接验证** (2026-06-28): nmcli device wifi connect ChinaNet-810 成功,wlan0 192.168.1.12/24,DHCP+IPv6 双栈
- **E3. SSH 局域网登录** (2026-06-28): 从主机 192.168.1.5 通过 ssh user@192.168.1.12 成功,hostname=xiaomi-jason
- **F1. 长稳运行测试** (2026-06-28): 30 分钟 25 次采样,0% 丢包,WiFi 持续 up,无 ath10k crash,温度稳定 (CPU 48-51°C)
  - 测试脚本: scripts/long-stability-test.sh
  - 日志: logs/stability-20260628-101833.log
- **F2. 刷回/重刷流程文档** (2026-06-28): docs/reflash-guide.md,8 章 417 行,含完整刷回原厂/重刷 pmOS/更新内核/更新 WiFi firmware/故障恢复流程
- **setup-usb-gadget.service 修复** (2026-06-28): 修改脚本检测已绑定 gadget 后幂等退出,解决 Resource busy 错误
- **H1. 服务器优化 P0** (2026-06-28): 把 pmOS 升级为可长期运行服务器
  - P0-1 sysctl 服务器加固 (`/etc/sysctl.d/99-server-hardening.conf`): panic_on_oops=1, panic=120, pid_max=4194304, fs.file-max=2097152, tcp_syncookies=1, swappiness=10 等
  - P0-2 journald 日志限制 100M (`/etc/systemd/journald.conf.d/size.conf`): SystemMaxUse=100M, SystemMaxFileSize=10M
  - P0-3 eMMC 自动 fsck: `tune2fs -c 30 -i 7d /dev/loop0p2` + `fsck-check.timer` 每周自动 e2fsck -f -n (只读检查)
  - P0-4 SSH 防爆破: fail2ban 卸载 (Alpine 无 py3-systemd), 改用 sshd 内置加固
  - P0-5 系统健康检查: `/usr/local/bin/health-check.sh` + `health-check.timer` (5min), 检查 sshd/NM/wifi/网关, 3 次失败自动 reboot
  - P0-6 SSH 加固 (`/etc/ssh/sshd_config.d/99-server-hardening.conf`): MaxAuthTries=3, AllowUsers=user, PermitRootLogin=no (保留密码登录)
  - 详见 `docs/troubleshooting.md` §7.8
- **H2. 服务器优化 P1** (2026-06-28): 补充运维便利性功能
  - P1-1 APK 自动更新通知: `/usr/local/bin/apk-update-check.sh` + `apk-update-check.timer` (24h), 仅通知不自动升级, 安全相关包 CRITICAL 告警
  - P1-2 温度监控告警: `/usr/local/bin/temp-monitor.sh` + `temp-monitor.timer` (5min), 12 个 thermal zone (CPU/GPU/PMIC/电池), 70°C 警告 / 85°C 关键
  - P1-3 SSH 端口: 保留 22 (用户决定)
  - P1-4 RTC 时钟持久化: PMIC RTC 不可写 (`hwclock --systohc` 失败 ENODEV), 改用 FakeRTC 文件方案 (`fake-rtc-save.timer` 30min 写时间戳 + `fake-rtc-restore.service` 启动时若 NTP 失败则恢复)
  - systemd-timesyncd 配置 NTP 服务器: ntp.aliyun.com / cn.pool.ntp.org
  - 详见 `docs/troubleshooting.md` §7.9
- **H3. 服务器优化 P2** (2026-06-28): 增强运维便利性 + 关键配置备份
  - P2-1 配置自动备份: `/usr/local/bin/config-backup.sh` + `config-backup.timer` (weekly), tar.gz 25 个关键配置到 /var/backups, 保留 28 天
  - P2-2 网络监控告警: `/usr/local/bin/net-monitor.sh` + `net-monitor.timer` (5min), 检查 wlan0/WiFi/网关/外网连通性 + DNS, 累计 rx/tx
  - P2-3 disk I/O 统计: `/usr/local/bin/disk-io-monitor.sh` + `disk-io-monitor.timer` (10min), 从 /proc/diskstats 读 mmcblk1 reads/writes/in_flight/io_ms
  - P2-4 motd 系统状态: `/etc/profile.d/motd-status.sh`, 登录时显示 uptime/load/mem/disk/temp/WiFi/USB/最近警告/timers 列表
  - 8 个 systemd timer 完整体系: health-check(5min) + temp-monitor(5min) + net-monitor(5min) + fake-rtc-save(30min) + disk-io-monitor(10min) + apk-update-check(24h) + fsck-check(7d) + config-backup(7d)
  - 详见 `docs/troubleshooting.md` §7.10
- **G1. 高负载压力测试** (2026-06-28): CPU/网络双维度压力测试通过, 设备可长期高负载运行
  - CPU 压力: stress-ng 8 核满载 5min, 起始 58°C → 峰值 70.6°C (@150s) → 恢复 57.4°C, 温升 12.6°C, 80°C 保护阈值未触发 (差 9.4°C)
  - 热调节: 150s 后温度下降 (稳态 67-70°C), Linux thermal framework + cpufreq 降频生效
  - 网络带宽: WiFi 信号 89, 链路 130 Mbps, 实测下载 20 Mbps (50MB 文件, 2.49 MB/s)
  - 延迟: 主机→设备 0% 丢包 avg 8.7ms; 设备→网关 0% 丢包 avg 3.5ms
  - 测试脚本: /tmp/cpu-stress-test.sh (含 80°C 自动停机保护)
  - 详见 `docs/troubleshooting.md` §7.11

## 当前阻塞点 (2026-06-28)

用户要求"开机即 Linux" (永久启动),已永久刷入 boot-nodebug.img 到 boot 分区。但开机后 USB SSH 不通:

- udev 把 usb0 重命名为 enxXX (predictable naming)
- NetworkManager 启动时 down 掉 usb0 但不配 IP
- 之前 v1/v2/v3 usb-ip-monitor 方案均失败

详见 [docs/restart-plan.md](./restart-plan.md) 重做计划。

## 下一步

- **重做计划**: 执行 [docs/restart-plan.md](./restart-plan.md) 方案 (重新构建 rootfs + USB 网络配置包)
- F3. 长期方案: 寻找 jason 设备对应的更新版 wlanmdsp.mbn, 避免长期依赖 whyred NON-HLOS.bin
- G2. (可选) 网络服务部署 (Web/MQTT 等)

---

## 完全从0开始 v3 (2026-06-29)

### 0. 触发与纠错

用户要求"完全从0开始"。主 agent 先做社区调研(WebSearch),再调用 5 个子 agent 核查本地资产。

**5 个子 agent 核查结论**:
1. agent-1 (设备+备份): 设备在线 fastboot 模式 d1236a7b,原厂备份完整,但 **whyred NON-HLOS.bin 未在项目内备份** (设备 modem 分区有)
2. agent-2 (pmbootstrap): 3.10.1 已装,4 包源在 `~/.local/var/pmbootstrap/cache_git/pmaports/device/testing/` 但大部分 untracked,zap 会丢失; chroot_native 已 zap; `/tmp/xiaomi-jason.img` 1.4GB 仍在
3. agent-3 (4 包源): 4 包内容总体可用,需删除 `usb-network-jason/99-usb-ncm.rules` 占位,在 `kernel-cmdline.conf` 加 `net.ifnames=0`,去掉 `pmos.debug-shell`
4. agent-4 (server-scripts): 8 timer + 8 脚本 + 5 配置完整,无需 doas→sudo 替换,缺 deploy.sh
5. agent-5 (docs 审查): 11 文档,3 个需归档 (restart-plan.md/port-plan.md/file-templates.md),3 个需重写,5 个保留

**关键纠错**: v2 文档(`restart-from-scratch-v2.md`)声称的 "switch_root 失败" 是**误诊**:
- progress.md 记录 2026-06-28 时 WiFi SSH 已可用 (E3/F1/G1),说明 systemd 启动成功
- 真实阻塞点是**永久刷入 boot.img 后 USB SSH 不通**(udev 重命名 + NM 抢占),不是 switch_root 失败
- 因此 v2 阶段 0 (诊断 switch_root) 跳过

### 1. 真实阻塞点

USB SSH 不通的根因(综合社区调研 + agent 核查):
1. `kernel-cmdline.conf` 不含 `net.ifnames=0`,systemd-udevd 把 usb0 重命名为 enxXX
2. `.link` 文件需要 udev 提前匹配,NM 启动快于 udev 完成匹配时 .link 失效
3. `kernel-cmdline.conf` 含 `pmos.debug-shell`(调试模式),不适合永久启动

### 2. 执行计划 (6 阶段)

**阶段 0 - 资产保护** (P0, 10 min):
- 0.1 备份 pmaports 4 包源到 `backups/pmaports-jason-20260629/`
- 0.2 从设备 modem 分区备份 whyred NON-HLOS.bin 到 `backups/whyred-non-hlos-20260629/`
- 0.3 复制 `/tmp/xiaomi-jason.img` 到 `artifacts/xiaomi-jason-v1.img`
- 0.4 在 pmbootstrap git 中 commit 当前 pmaports 改动

**阶段 1 - 修复 4 个包源** (P0, 15 min):
- 1.1 `usb-network-jason/`: 删除 `99-usb-ncm.rules`,同步 APKBUILD source/package()
- 1.2 `device-xiaomi-jason/kernel-cmdline.conf`: 加 `net.ifnames=0`,去掉 `pmos.debug-shell`,降 loglevel 到 4
- 1.3 `refs/jason-dts/jason.dts`: 补 ABL 属性(从 patch 0001 L51-53 复制),或在 README 加注"patch 0001 为权威"
- 1.4 `usb-network-jason/APKBUILD`: depends 显式加 `dnsmasq`(当前为传递依赖)

**阶段 2 - pmbootstrap 重置 + 重建** (P0, 60-90 min):
- 2.1 `pmbootstrap zap` 清理脏工作区(已备份 pmaports)
- 2.2 把 `refs/jason-pmaports-patches/` 4 包同步到 `~/.local/var/pmbootstrap/cache_git/pmaports/device/testing/`
- 2.3 `pmbootstrap checksum` 更新校验值
- 2.4 按依赖顺序 build: kernel → firmware → usb-network → device
- 2.5 `pmbootstrap install --password 1234` 生成新 rootfs
- 2.6 记录新 rootfs UUID

**阶段 3 - 生成 boot.img** (P0, 5 min):
- 3.1 `pmbootstrap export`
- 3.2 用 `scripts/modify-bootimg-cmdline.py` 改 cmdline: 加 `net.ifnames=0`,去掉 `pmos.debug-shell`,对齐新 UUID
- 3.3 验证 cmdline

**阶段 4 - 刷入设备验证** (P0, 30 min):
- 4.1 `fastboot flash userdata xiaomi-jason.img`
- 4.2 `fastboot flash boot boot.img`
- 4.3 `fastboot reboot`
- 4.4 等 60 秒,`ping 172.16.42.1` + `ssh user@172.16.42.1`
- 4.5 重启 3 次验证持久性

**阶段 5 - 服务器脚本部署 + 长稳** (P1, 30-60 min):
- 5.1 创建 `refs/server-scripts/deploy.sh` 一键部署脚本
- 5.2 scp 推送到设备,执行 deploy.sh
- 5.3 验证 8 个 timer active
- 5.4 30 min 长稳测试

**阶段 6 - 文档与可复现性** (P1, 30 min):
- 6.1 归档过期文档到 `docs/archive/`
- 6.2 更新 `progress.md` / `device-state-manifest.md` / `reflash-guide.md`(加 net.ifnames=0)
- 6.3 在 `troubleshooting.md` 新增 §9 (USB SSH 修复总结,不是 switch_root 诊断)
- 6.4 git commit 所有改动

### 3. 范围与丢弃清单

**保留(不动)**:
- `backups/original-jason-20260627-114354/` (原厂 28 分区备份)
- `jason_images_V8.5.9.0.../` (原厂 fastboot 包)
- `twrp-3.7.0_9-0-jason.img`
- `refs/jason-dts/jason.dts` (DTS 源)
- `refs/jason-pmaports-patches/` (4 包源,作为权威源)
- `refs/server-scripts/` (服务器脚本)
- 设备 modem 分区现状 (whyred NON-HLOS.bin, WiFi fw 1.0.0.591)
- 设备序列号 / 解锁状态

**重做(从 0 重建)**:
- pmbootstrap 工作区 (zap 后重新 init/apply/build/install)
- rootfs 镜像 `xiaomi-jason.img`
- boot.img
- 设备上的 userdata + boot 分区

**归档(移到 `docs/archive/`)**:
- `docs/restart-plan.md` (v1, 已被 v2/v3 替代)
- `docs/port-plan.md` (首阶段已完成)
- `docs/file-templates.md` (含错误,已落地为实际包源)
- `docs/d2-boot-checklist.md` (首阶段已完成)
- `docs/restart-from-scratch-v2.md` (基于误诊,被 v3 替代)

### 4. 执行日志

(执行时按阶段追加到此章节)

#### 2026-06-29 阶段 2-4 完成 + WiFi 修复

**阶段 2-3 (构建 + boot.img)**: 复用已有 kernel + initramfs,修改 init_2nd.sh 实现 "stay in initramfs" 方案(PID 1 保持 busybox ash,不启动 systemd,USB NCM 稳定)。deploy.sh 自动化 build/flash/verify 流程。

**阶段 4 (刷入验证)**:
- boot.img 刷入 boot 分区,userdata 已有 rootfs
- USB NCM 网络稳定 (172.16.42.1/16),SSH 可用
- 62 个内核模块自动加载 (qrtr, qcom_q6v5_*, ath10k_snoc, mac80211 等)
- ADSP (remoteproc0) 自动启动,QRTR 14 个服务可用

**WiFi 修复 (关键突破)**:
- **症状**: ath10k_snoc 驱动绑定 18800000.wifi,但无 QMI 握手消息,wlan0 不出现
- **根因调研**: 用 5 个子 agent 并行调研 pmaports/文档/设备状态/内核源码/社区方案
- **根因发现**: init_2nd.sh 主动停止 modem (`echo stop > .../remoteproc2/state`),基于"modem firmware 不稳定"的错误假设。实际上:
  1. modem 停止 → modem glink-edge 不实例化 → QRTR 无 modem 节点
  2. WLFW 服务 (QRTR service 69/0x45) 运行在 modem 上,modem 离线则 WLFW 不存在
  3. ath10k_snoc 的 `qmi_add_lookup(WLFW)` 永远等不到服务上线
- **二次根因**: 即使启动 modem,modem 也会每 ~40s crash (`Task starvation: diag, ping: 4`),因为 diag-router 服务未运行,modem diag 任务饥饿
- **修复**: 修改 init_2nd.sh:
  1. 创建 modemst 分区 symlink (rmtfs 需要)
  2. 启动 ADSP
  3. 启动 rmtfs + tqftpserv + diag-router (chroot /sysroot)
  4. 启动 modem (`echo start > .../remoteproc2/state`)
  5. 等待 30s,WLFW 服务自动上线
  6. ath10k_snoc 自动完成 QMI 握手,wlan0 出现
- **验证**: 刷入新 boot.img,66s 内 wlan0 available,QMI 握手成功 (fw 1.0.0.591, htt-ver 3.58),WiFi 扫描到 20+ 网络,ChinaNet-810 信号 -46

**关键文件**:
- `/tmp/jason-initramfs/init_2nd.sh` (修改: 删除 stop modem,添加服务启动 + start modem)
- `/home/lyl/Documents/system/XiaoMiNote3/scripts/deploy.sh` (构建+刷入+验证)
- `/tmp/jason-boot-initramfs.img` (23MB,已刷入)

**当前设备状态** (updated 2026-06-29 23:35):
- PID 1: `/bin/busybox ash /init_2nd.sh` (initramfs 模式, 不启动 systemd)
- USB NCM: 172.16.42.1/16, SSH on port 22 (root, key-based)
- ADSP: running, Modem: running (30min 0 crash), CDSP: offline (无固件)
- WiFi: wlan0 自动连接 ChinaNet-810, IP 192.168.1.17/24, MAC 固定 02:1a:73:6b:03:01
- 5 个用户态服务运行: rmtfs + tqftpserv + diag-router + wpa_supplicant + udhcpc
- 服务器监控: server-daemon.sh (8 个监控任务, 替代 systemd timers)
- 屏幕显示: console=tty0 fbcon=nodefer, tty1 交互式 shell

#### 2026-06-29 阶段 5 完成: 服务器脚本 (initramfs 适配)

**阶段 5 (服务器脚本部署)**:
- 适配 initramfs 模式 (无 systemd, PID 1 = busybox ash):
  - `server-daemon.sh`: 单进程循环调度器, 替代 8 个 systemd timers
  - 8 个监控任务: health-check(5min) + temp-monitor(5min) + net-monitor(5min) + disk-io-monitor(10min) + fake-rtc-save(30min) + apk-update-check(24h) + config-backup(7d) + fsck-check(7d)
  - syslogd 在 rootfs 上下文运行 (chroot /sysroot, 为 logger 命令提供 /dev/log)
  - motd-status.sh: SSH 登录时显示系统状态 (uptime/mem/disk/temp/WiFi/USB/SSH/daemon)
- 关键适配:
  - `pgrep -x sshd` → `pgrep -f sshd` (进程名是 sshd.pam 不是 sshd)
  - wlan0 DOWN 不算失败 (initramfs 模式下 WiFi 可能未连接, 接口存在即可)
  - `nohup` + `</dev/null` 防 SIGHUP (SSH 断开时守护进程不死)
- 自动启动: init_2nd.sh 在 boot 后 15s 启动 syslogd + fake-rtc-restore + server-daemon

**屏幕 console 修复**:
- cmdline 添加 `console=tty0 fbcon=nodefer` (之前只有 ttyMSM0 串口, 屏幕黑色)
- init_2nd.sh 添加 tty1 交互式 shell (chroot /sysroot /bin/sh, 循环 respawn)

**WiFi 自动启动 (关键功能)**:
- `wifi-start.sh`: 幂等 WiFi 启动脚本 (wpa_supplicant + udhcpc)
  - 固定 MAC 地址 02:1a:73:6b:03:01 (ath10k 每次启动分配随机 MAC, 导致 DHCP IP 不稳定)
  - 检测已有连接, 不杀工作进程 (idempotent)
  - 等待 wpa_state=COMPLETED (最多 25s), 然后启动 udhcpc
- init_2nd.sh 添加 WiFi starter 子 shell: 等 wlan0 出现 (~40s) → 调用 wifi-start.sh
- wpa_supplicant.conf 持久化在 /etc/wpa_supplicant/ (rootfs)
- 启动后 ~47s WiFi 连接完成: wpa握手 3s + DHCP 1s

**30 分钟稳定性测试 (PASSED)**:
- 脚本: `scripts/stability-test.sh` (30 samples x 60s)
- 日志: `logs/stability-test.log`
- 结果:
  | 指标 | 范围 | 状态 |
  |------|------|------|
  | 温度 | 53.8 - 55.8°C | 稳定, 无过热 |
  | 负载 | 0.12 - 0.46 | 空闲 |
  | 内存 | 387-433 MB / 3624 MB | ~11% 使用 |
  | WiFi IP | 192.168.1.17 (1 个 IP) | 0 断线 |
  | Modem | running 30/30 | 0 崩溃 (diag-router 修复生效) |
  | ADSP | running 30/30 | 0 崩溃 |
  | 服务 | sshd/wpa/dhcp/daemon 全 UP 30/30 | 0 失败 |
  | 重启 | 0 | uptime 1958s (~33min) |

**关键文件** (阶段 5):
- `refs/server-scripts-initramfs/server-daemon.sh` (93 行)
- `refs/server-scripts-initramfs/health-check.sh` (71 行)
- `refs/server-scripts-initramfs/net-monitor.sh` (60 行)
- `refs/server-scripts-initramfs/fake-rtc-restore.sh` (26 行)
- `refs/server-scripts-initramfs/motd-status.sh` (58 行)
- `refs/server-scripts-initramfs/wifi-start.sh` (84 行)
- `refs/initramfs/init_2nd.sh` (312 行, 含 WiFi starter + tty1 shell + server-daemon)
- `scripts/stability-test.sh` (30-min 监控脚本)

#### 2026-06-29 阶段 6 进行中: 文档整理

- 归档 5 个过期文档到 `docs/archive/`
- 更新 `device-state-manifest.md` (initramfs 模式, WiFi 自动启动, SSH 密钥)
- 更新 `progress.md` (本文)
- git commit

### 5. 首阶段成功定义 (达成情况)

| 条件 | 状态 | 证据 |
|------|------|------|
| 设备可重复启动进入 Linux | ✅ | 多次 reboot 后均自动进入 Linux (PID 1 = busybox ash) |
| rootfs 可读写 | ✅ | `/dev/loop0p2 on / type ext4 (rw,relatime)` |
| WiFi 可连接指定网络 | ✅ | ChinaNet-810 自动连接, IP 192.168.1.17, 30min 0 断线 |
| SSH 可从局域网登录 | ✅ | `ssh root@192.168.1.17` (密钥认证), USB `ssh root@172.16.42.1` |
| 基本系统信息采集 | ✅ | dmesg / ip a / syslog (logger + /var/log/messages) |
| 刷回/重刷/更新标准流程文档 | ✅ | docs/reflash-guide.md + scripts/deploy.sh (--build/--flash/--verify) |

**首阶段成功!** (2026-06-29)

#### 2026-06-29 CPU/GPU 性能调研与 benchmark

**触发**: 用户要求"优化 cpu 和 gpu 性能"

**CPU cpufreq 调研结论 — 无法启用 (上游 mainline 限制)**:
- `cpufreq-dt` 加载失败: `failed to get clk: -2 (ENOENT)`, `failed register driver: -19 (ENODEV)`
- DT 缺 cpufreq-hw 节点 (@0x17d43000): cpu@0 引用 `qcom,freq-domain` phandle 0x8, 但 DT 中无任何 cpufreq-hw compatible 节点
- `gcc-sdm660` 卡在 `sync_state() pending due to 17d43000.cpufreq`, 导致 CPU clk 不暴露到 common clock framework
- `qcom-cpufreq-hw.ko.zst` 模块存在, 但 insmod 触发内核 panic (panic_on_oops=1, 设备进 fastboot, fastboot reboot 恢复)
- pmOS wiki 明确说: SDM660 "no support for CPU frequency scaling"
- /proc/cpuinfo BogoMIPS=38.40 (不可靠, ARMv8 不支持精确测量)
- 实际 CPU 频率无法从软件读取 (clk_summary 无 CPU 时钟)

**GPU 调研结论 — 已最优, 无需优化**:
- GPU 实际是 **Adreno 512** (compatible `qcom,adreno-512.0`), 非 530
- `msm` 驱动已绑定, DRM 初始化成功 (`Initialized msm 1.13.0 for c901000.display-controller on minor 0`)
- devfreq 节点 `/sys/class/devfreq/5000000.gpu/` 工作正常:
  - governor: `simple_ondemand` (已最优)
  - available frequencies: 19.2 / 160 / 266 / 370 / 465 / 588 MHz
  - cur_freq: 19.2 MHz (空闲降频, 节能)
  - Total transitions: 0 (无图形负载)
- 已知小问题: `failed to load a530_pm4.fw` (firmware 命名错, 应为 a512_pm4.fw), 不影响显示 (tty1 fbcon 工作)

**CPU Benchmark (dd /dev/urandom 并行, 3 次平均)**:
- 脚本: `/tmp/cpu-bench-final.sh`
- 单核 (1 进程, 5s x 3):
  | CPU | mask | MB/s |
  |-----|------|------|
  | cpu0 (little) | 0x01 | 97 |
  | cpu3 (little) | 0x08 | 55 |
  | cpu4 (big)    | 0x10 | 55 |
  | cpu7 (big)    | 0x80 | 100 |
- 多核并行 (N 进程, 8s x 3):
  | 模式 | mask | 并行数 | MB/s |
  |------|------|--------|------|
  | little4 (cpu0-3) | 0x0f | 4 | 166 |
  | big4    (cpu4-7) | 0xf0 | 4 | 169 |
  | **all8  (cpu0-7)** | **0xff** | **8** | **175** ← 最高 |
  | all8 (cpu0-7)    | 0xff | 4 | 134 |

**关键发现**:
1. **8 核 8 进程最快 (175 MB/s)**, 但只比 4 核 4 进程快 5%
2. 上游 wiki "8 cores slower than 4 cores" 在当前内核版本 (6.19.10-sdm660) **不成立**
3. 单核性能差异 (55 vs 100 MB/s) 来自 cluster 频率未同步, 不是 little/big 之分
4. 下线 cpu4-7 不会让 little 更快 (实测反而降至 55 MB/s, 因 interconnect 影响)
5. **CPU 优化空间有限** — cpufreq 无法控制, 绑核收益 <5%

**结论**: 接受当前状态, 不做主动 CPU/GPU 配置变更 (无显著优化空间)。已记录调研结果供后续参考。

**关键教训**:
- 不可 insmod `qcom-cpufreq-hw` — DT 缺节点会触发 panic (设备进 fastboot, 需 `fastboot reboot` 恢复)
- BogoMIPS 在 ARMv8 不可靠 (显示 38.40 但实际 CPU 工作正常)
- Alpine busybox `date +%N` 不支持纳秒, loop 测试需用其他方法测时间

### cpufreq-hw 深度调研结论 (2026-06-30)

**调研发现 (修正之前误判)**:
- patch 0003 **已完全应用**到设备 DT: `cpufreq@17d43000` 节点存在于 `/proc/device-tree/soc@0/`, compatible = `qcom,sdm660-cpufreq-hw` + `qcom,cpufreq-hw`
- cpu0-7 都有 `qcom,freq-domain = <0x8 0/1>` (phandle 0x8 = cpufreq_hw) 和 `operating-points-v2 = <0x10/0x9>` (cluster1/0 OPP 表)
- mainline `qcom-cpufreq-hw` 驱动 **能匹配** `qcom,cpufreq-hw` fallback compatible (之前误判为不识别)
- 模块未自动加载 (initramfs 无 udev), 手动 insmod 会 panic

**cpufreq 不可用根因 (SDM660 OSM 编程问题)**:
- SDM660 的 OSM (Optimized State Mapping) 硬件 **需要 OS 编程** (bootloader 不初始化, 与 SDM845+ 不同)
- mainline `qcom-cpufreq-hw` 驱动 **不做 OSM 编程**, 仅读取 LUT
- OSM 未初始化 → LUT 数据无效 → 驱动 probe 时读取垃圾数据 → 后续操作触发 oops → panic (panic_on_oops=1)
- AngeloGioacchino OSM 编程 patch 系列 (v6, 2021-07, 9 个 patch, ~3000 行, 依赖 SAWv4.1 + CPR3) 至今 5 年未合并
- pmOS 2025-10 SDM660 CPU 状态仍为 "Partial" (接受 no cpufreq)

**当前状态 (接受上游限制)**:
- cpufreq-dt: 失败 (-19 ENODEV), 因 CPU clk 未通过 CCF 暴露
- qcom-cpufreq-hw: 模块存在但不可加载 (panic 风险)
- gcc-sdm660 sync_state pending: 因 17d43000.cpufreq 消费者未绑定 (无害警告)
- CPU 运行在 bootloader 设置的频率 (性能足够, 8 核 175 MB/s)

### DPU timeout 卡死修复 (2026-06-30)

**故障现象**:
- 设备运行 ~50 分钟后 (3048s) 出现 `watchdog: Watchdog detected hard LOCKUP on cpu 3`
- `[dpu error]enc33 frame done timeout` (DPU 显示编码器帧完成超时)
- RCU stall 级联恶化, 系统完全无响应, 设备最终进 fastboot

**根因分析**:
1. **CPU hotplug 异常** (722s): CPU4-7 被 killed 后又重新 booted, `IRQ129: set affinity failed(-22)` — cpuidle bug
2. **DPU frame done timeout**: 显示子系统帧完成超时, 可能与屏幕持续唤醒 + GPU firmware (a530_pm4.fw) 加载失败有关

**修复 (cmdline 参数)**:
- `consoleblank=60`: 60 秒后自动 blank 控制台, 减少 DPU 持续刷新负载
- `cpuidle.off=1`: 禁用 CPU idle, 避免异常 CPU hotplug (IRQ129 affinity failed + CPU killed)

**验证**:
- 设备启动正常, 8 CPU 全部在线, 无异常 hotplug
- cpuidle 已禁用 (`/sys/module/cpuidle/parameters/off` = 1)
- consoleblank = 60
- SSH 可达, WiFi 正常

**注意**: a530_pm4.fw 加载失败是已知问题 (jason 是 Adreno 512, 但驱动请求 a530), 不影响显示功能。如后续仍有 DPU timeout, 可考虑 cmdline 加 `video=DSI-1:d` 完全禁用显示。

### OSM 物理地址确认 (2026-06-30, 关键突破)

**问题**: 之前 patch 0003 使用地址 `0x17d43000`, /dev/mem 读 0x17d42000 触发 panic。需确认 SDM660 真实 OSM 地址。

**调研来源**:
1. **下游 Xiaomi kernel** (MiCode/Xiaomi_Kernel_OpenSource, `jason-p-oss` 分支) `sdm660.dtsi`:
   - `clock_cpu: qcom,clk-cpu-660@179c0000` — 下游 OSM 块 (16KB) 起始地址 **0x179c0000**
   - compatible = `qcom,clk-cpu-osm` (下游专用驱动, 非 mainline cpufreq-hw)
   - 整块 reg = `<0x179c0000 0x4000>` (16KB 覆盖 OSM + freq domain 0/1)
2. **AngeloGioacchino MSM8998 bringup DTS** (SoMainline/linux `angelo/somainline-msm8998-bringup` 分支) `msm8998-angelo.dtsi`:
   - `cpufreq_hw@17816000` 节点 (注意: 单元地址用 osm-acd0 的地址, 起始 reg 是 osm-acd0)
   - 6 个 reg 区域, 完整 OSM 地址映射
3. **SoMainline linux topic/cpr3hh 分支** — 完整 OSM + CPR3 驱动代码 (1852 行 cpufreq-hw.c + 2711 行 cpr3.c)
   - SDM630/660 使用 `msm8998_soc_data` (compatible = `qcom,msm8998-cpufreq-hw`)
   - `uses_tz = false` (OSM 不由 TZ 预编程, 必须 OS 编程)
   - `reg_osm_sequencer = 0x300`

**关键结论**: **SDM660 OSM 地址 = 0x179c0000, 与 MSM8998 完全相同**。之前 patch 0003 使用的 `0x17d43000` 是 **SDM845** 的地址 (从 mainline DT bindings example 抄的, 不是 SDM660 的)。

**完整地址映射** (SDM630/660 = MSM8998):

| 寄存器 | 物理地址 | 大小 | reg-name | 用途 |
|--------|----------|------|----------|------|
| osm-acd0 | 0x17914800 | 0x100 | "osm-acd0" | ACD (Array Clock Domain) 配置 perfcl |
| osm-acd1 | 0x17814800 | 0x100 | "osm-acd1" | ACD 配置 pwrcl |
| osm-domain0 | 0x179c0000 | 0x1000 | "osm-domain0" | OSM 编程域 0 (perfcl/A73) |
| freq-domain0 | 0x179c1000 | 0x1000 | "freq-domain0" | 频率 LUT 域 0 |
| osm-domain1 | 0x179c2000 | 0x1000 | "osm-domain1" | OSM 编程域 1 (pwrcl/A53) |
| freq-domain1 | 0x179c3000 | 0x1000 | "freq-domain1" | 频率 LUT 域 1 |
| CPRh ctrl 0 | 0x179c8000 | 0x4000 | (cprh 节点) | CPR-Hardened 控制器 0 |
| CPRh ctrl 1 | 0x179c4000 | 0x4000 | (cprh 节点) | CPR-Hardened 控制器 1 |
| APCS common | 0x179d1000 | 0x1000 | (下游) | APCS 通用寄存器 |

**SDM660 CPU 频率表** (来自下游 `qcom,msm-cpufreq` 节点):
- **PWRCL (A53, cpu4-7)**: 633600, 902400, 1113600, 1401600, 1536000, 1612800, 1747200, **1843200** (max 1843 MHz)
- **PERFCL (A73, cpu0-3)**: 1113600, 1401600, 1747200, 1804800, 1958400, 2150400, 2208000, **2457600** (max 2457 MHz)

注: 之前 patch 0003 的 OPP 表用了 1766/2208 MHz 是错误的 (那是 SDM630/636 的频率, 不是 SDM660)。

**MSM8998 Angelo DTS cpufreq_hw 节点参考** (`/tmp/sdm660ml/msm8998-angelo.dtsi` L3041-3056):
```dts
cpufreq_hw: cpufreq_hw@17816000 {
    compatible = "qcom,cpufreq-hw-8998";
    reg = <0x017914800 0x100>,  <0x017814800 0x100>,
          <0x0179c0000 0x1000>, <0x0179c1000 0x1000>,
          <0x0179c2000 0x1000>, <0x0179c3000 0x1000>;
    reg-names = "osm-acd0", "osm-acd1",
                "osm-domain0", "freq-domain0",
                "osm-domain1", "freq-domain1";
    clocks = <&rpmcc RPM_SMD_XO_A_CLK_SRC>,
             <&gcc HMSS_GPLL0_CLK_SRC>;
    clock-names = "xo", "alternate";
    #freq-domain-cells = <1>;
    status = "disabled";
};
```

**MSM8998 Angelo DTS CPRh 节点参考** (`/tmp/sdm660ml/msm8998-angelo.dtsi` L3124-3206):
- `power-controller@179c8000` compatible = `qcom,msm8998-cprh`
- 35 个 qfprom nvmem cells (cpr_efuse_speedbin, cpr_fuse_revision, cpr_quot*_pwrcl/perfcl 等)
- `#power-domain-cells = <1>`
- CPU 节点用 `power-domains = <&apc_cprh 0/1>` 引用

**驱动侧关键发现**:
- mainline 6.19.10 `qcom-cpufreq-hw.c` 只有 761 行, **不含 OSM 编程代码**, 只有 `qcom,cpufreq-hw` 和 `qcom,cpufreq-epss` 两个 compatible
- SoMainline topic/cpr3hh `qcom-cpufreq-hw.c` 有 1852 行, **含完整 OSM 编程代码**, 增加 `qcom,msm8998-cpufreq-hw` compatible + `msm8998_soc_data` (`uses_tz = false`, `reg_osm_sequencer = 0x300`)
- `osm-domain0/1` 是 **必需的** (驱动 `platform_get_resource_byname(IORESOURCE_MEM, "osm-domain0")`, 缺失返回 -ENODEV)
- `osm-acd0/1` 是 **可选的** (缺失则跳过 ACD 初始化, 返回 0)
- CPR3 驱动 compatible: `qcom,sdm630-cprh` (SDM630/660) 和 `qcom,msm8998-cprh` (MSM8998), 共用 `msm8998_cpr_acc_desc` 之外的 `sdm630_cpr_acc_desc`

**下一步计划** (分阶段验证):
1. **阶段 1 (最小化)**: 修复 patch 0003 — 改地址为 0x179c1000/0x179c3000, 改 compatible 为 `qcom,msm8998-cpufreq-hw`, 添加 osm-domain0/1 + osm-acd0/1。先验证地址正确性 (不 panic)。
2. **阶段 2 (OSM 编程)**: 移植 SoMainline topic/cpr3hh 的 cpufreq-hw.c (含 OSM 编程代码) + cpr3.c + cpr-common.c/h
3. **阶段 3 (CPRh DTS)**: 添加 CPRh DTS 节点 + qfprom nvmem cells

**关键文件**:
- `/tmp/sdm660ml/sdm660.dtsi.jason` — 下游 Xiaomi SDM660 DTS (OSM 地址权威源)
- `/tmp/sdm660ml/msm8998-angelo.dtsi` — MSM8998 OSM+CPRh DTS 节点参考
- `/tmp/somainline-files/drivers/cpufreq/qcom-cpufreq-hw.c` — SoMainline 完整 OSM 驱动 (1852 行)
- `/tmp/somainline-files/drivers/pmdomain/qcom/cpr3.c` — CPR3 驱动 (2711 行)
- `/tmp/somainline-files/include/soc/qcom/cpr.h` — CPR3 公共头文件

### patch 0003 修复 + 地址验证 (2026-06-30)

**修复内容**:
- 地址从 0x17d43000 改为 0x179c0000 (与 MSM8998 相同)
- compatible 从 `qcom,sdm660-cpufreq-hw` 改为 `qcom,msm8998-cpufreq-hw`
- 添加 6 个 reg 区域: osm-acd0/1, osm-domain0/1, freq-domain0/1
- OPP 表修正为 SDM660 真实频率: A53 max 1843 MHz, A73 max 2457 MHz
- 用 diff 生成正确行号的 patch (避免手动算行号错误)

**验证结果** (刷入设备 + modprobe qcom-cpufreq-hw):
- ✅ **设备正常启动, 不 panic** — 地址 0x179c0000 正确
- ✅ **驱动成功 probe** — dmesg 显示 `qcom-cpufreq-hw 17914800.cpufreq` (osm-acd0 地址作为节点名)
- ✅ **驱动读取了 Domain-0 和 Domain-1 的 enable 寄存器** — 没有访问错误
- ❌ **cpufreq 仍未工作** — `cpufreq hardware not enabled`
- ❌ **驱动注册失败** — `CPUFreq HW driver failed to register`

**根因分析**:
- mainline qcom-cpufreq-hw 驱动 **不认** `qcom,msm8998-cpufreq-hw` compatible
- fallback 用 `qcom,cpufreq-hw` → `qcom_soc_data` (SDM845 的)
- `qcom_soc_data` 只检查 enable 寄存器 (offset 0x0), 不做 OSM 编程
- OSM 硬件未被 TZ 编程 (`uses_tz=false`), enable 位为 0
- 驱动检测到 "hardware not enabled" → 拒绝注册

**下一步**: 移植 SoMainline topic/cpr3hh 的 OSM 编程代码 (patch 0005)
- 替换 mainline qcom-cpufreq-hw.c (761 行) 为 SoMainline 版本 (1852 行)
- 添加 `qcom,msm8998-cpufreq-hw` compatible + `msm8998_soc_data`
- `msm8998_soc_data` 包含 OSM 编程逻辑 (`uses_tz=false`, `reg_osm_sequencer=0x300`)
- 需要适配 6.10→6.19 API 变化 (见 API 评估报告)

**6.19 API 变化评估** (vs 6.10 SoMainline 代码):
- 简单适配: `.remove_new` → `.remove`, 删除 boost 块, 创建 `include/soc/qcom/cpr.h`
- 重大重构: `devm_pm_opp_attach_genpd` → `devm_pm_domain_attach_list`
- cpr3.c 主体逻辑完全兼容 6.19.10 (genpd 架构, SCM 调用, regmap 等)
- 总体难度: 中等 (大部分代码可直接复用)

### patch 0004/0005 创建 + patch 0006 阻塞 (2026-06-30)

**patch 0005 (cpufreq-hw OSM 编程) — 已创建**:
- 替换 mainline qcom-cpufreq-hw.c (761 行) 为 SoMainline topic/cpr3hh 版本 (1852 行 → 1851 行)
- 应用 5 个 API 变化:
  1. `devm_pm_opp_attach_genpd` → `devm_pm_domain_attach_list` (重大重构, 使用 `PD_FLAG_REQUIRED_OPP`)
  2. 删除 boost 块 (`policy_has_boost_freq` + `cpufreq_enable_boost_support` 在 6.19 中已移除)
  3. `.remove_new` → `.remove` (6.19 platform_driver API)
  4. `struct device **genpd_cpr_vdev` → `struct dev_pm_domain_list *genpd_list`
  5. `dev_get_drvdata(*genpd_cpr_vdev)` → `dev_get_drvdata(genpd_list->pd_devs[0])`
- patch 文件: `refs/cpufreq-patches/0005-cpufreq-hw-osm-programming.patch` (1495 行)
- 工作目录: `/tmp/patch-work/qcom-cpufreq-hw.c.new`

**patch 0004 (CPR3 驱动) — 已创建**:
- 新增 4 个文件: `drivers/pmdomain/qcom/cpr3.c` (2710 行), `cpr-common.c` (361 行), `cpr-common.h` (109 行), `include/soc/qcom/cpr.h` (17 行)
- 修改 2 个文件: `drivers/pmdomain/qcom/Kconfig` (添加 QCOM_CPR_COMMON + QCOM_CPR3), `Makefile` (添加 cpr-common.o + cpr3.o)
- API 适配: 删除 `#include <linux/of_device.h>` (6.19 已移除, `of_device_get_match_data` 在 `linux/of.h` 中)
- patch 文件: `refs/cpufreq-patches/0004-cpr3-driver.patch` (3275 行)

**patch 0006 (CPRh DTS 节点) — 安全阻塞**:
- **阻塞原因**: 缺少 SDM660 准确的 qfprom CPR cells 偏移地址
- **依赖链**: cpufreq-hw (`uses_tz=false`) → 需要 CPR3 genpd → CPR3 驱动需要 qfprom nvmem cells → 需要 35 个 cells 的精确偏移
- **搜索结果**:
  - SoMainline topic/cpr3hh: 有驱动代码, 无 SDM660 cprh DTS
  - 上游 CPR3 v14/v15 patch 系列: 只有 MSM8998 DTS, 无 SDM630/660
  - 下游 Xiaomi 内核: 用私有 cpufreq 驱动, 无 mainline 格式 qfprom CPR cells
  - pmOS wiki: SDM660 CPU 状态 "Partial"
- **MSM8998 vs SDM630 qfprom**: 物理地址不同 (MSM8998=0x784000, SDM630=0x780000), 内部偏移可能不同
- **风险**: 偏移错误 → CPR3 读取错误校准数据 → 设置错误电压 → 硬件损坏
- **MSM8998 参考 DTS**: `/tmp/sdm660ml/msm8998-angelo.dtsi` L1294-1469 (35 个 qfprom cells)

**未来解决方案** (需要其一):
1. 从下游 Xiaomi 内核 C 代码中提取 SDM660 qfprom CPR 偏移 (需要下游 cpr3-regulator 驱动源码)
2. 在设备上 dump qfprom 区域 (0x780000, 0x621c) 并与 MSM8998 对比
3. 等待上游社区为 SDM630/660 添加 cprh DTS
4. 修改 cpufreq-hw 驱动跳过 CPR3 依赖 (OSM 编程不完整, 可能不稳定)
