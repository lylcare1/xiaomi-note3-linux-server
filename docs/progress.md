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

**当前设备状态**:
- PID 1: `/bin/busybox ash /init_2nd.sh` (initramfs 模式)
- USB NCM: 172.16.42.1/16,SSH on port 22
- ADSP: running,Modem: running,CDSP: offline (无固件)
- wlan0: 存在,QMI 握手成功,可扫描
- 3 个用户态服务运行: rmtfs + tqftpserv + diag-router
- 无 modem crash

**待办**:
- 阶段 5: 服务器脚本部署 (需适配 initramfs 模式,无 systemd timers)
- 阶段 6: 归档过期文档,更新 device-state-manifest.md,git commit
