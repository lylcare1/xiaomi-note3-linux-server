# 项目交接文档 (Handover)

> 生成日期: 2026-07-02 | 最后更新: 2026-08-29 15:30
> 上一会话最后操作: **Ubuntu 24.04.4 移植完成并稳定运行** — userdata 刷入 Ubuntu rootfs (pmOS 内核 r36 复用), boot.img 持久化 (modem 永久 blacklist), WiFi 因 modem 生态问题搁置 (见 §7.10), USB SSH/NTP/电量监控正常
> 项目根目录: `/home/lyl/Documents/system/XiaoMiNote3`

---

## 1. 项目目标

将 **Xiaomi Mi Note 3 (jason, SDM660)** 改造为无头 Linux 服务器（通过 USB NCM 可 SSH 访问，支持 WiFi，无 Android，长期稳定运行）。

**首阶段成功定义**（已达成）：
- ✅ 设备可重复启动进入 Linux
- ✅ rootfs 可读写
- ✅ WiFi 可连接指定网络
- ✅ SSH 可从局域网/USB 登录
- ✅ 具备 dmesg / ip a / journalctl 能力
- ✅ 具备刷回/重刷/更新内核的标准流程文档

详见 [AGENTS.md](./AGENTS.md)。

---

## 2. 设备当前状态

### 2.1 运行状态
- **设备状态**: 运行中 (2026-08-29 15:20), SSH/USB 正常; **系统已切换为 Ubuntu 24.04.4 rootfs**
- **当前网络**: USB NCM `172.16.42.1` (唯一通道); WiFi 不可用 (modem 永久禁用, 见 §7.10)
- **开机后**: 自动进入 Linux（boot 已持久化，无需 fastboot boot）

### 2.2 系统配置
| 项 | 值 |
|---|---|
| 设备 | Xiaomi Mi Note 3 (jason) |
| SoC | Qualcomm SDM660 (8 核: 4×A53 + 4×A73) |
| 内存 | 6 GB (实际 3.6G 可见) |
| 存储 | 128 GB eMMC (userdata 51G rootfs) |
| 系统 | **Ubuntu 24.04.4 LTS (noble) arm64** — 用户空间 Ubuntu, 内核仍 pmOS r36 |
| 内核 | `6.19.10-sdm660` (r36, #36-postmarketos-qcom-sdm660) |
| 内核特性 | cpufreq-hw + softdog watchdog + msm-poweroff 补丁 (0009) |
| init 系统 | systemd (PID 1 = systemd) |
| USB 连接 | NCM gadget (usb-gadget.service), 设备 IP `172.16.42.1/16` |
| SSH 用户 | `user` (密码 `DEVICE_PASS_PLACEHOLDER`) |
| WiFi | **不可用** — modem 永久 blacklist (见 §7.10); pmOS 时代可用的方案见 §7.8 |
| 电池 | qcom-battery: 容量/状态/charge_behaviour 可读 (96% Full @ 2026-08-29) |
| Bootloader | unlocked |

### 2.3 关键密码
- 设备 user 密码: `DEVICE_PASS_PLACEHOLDER`
- 主机 sudo 密码: `HOST_SUDO_PASS_PLACEHOLDER`
- GitHub: `lylcare1` / `GH_TOKEN_PLACEHOLDER`

---

## 3. 连接方式

### USB NCM（首选，开机即用）
```bash
sshpass -p 'DEVICE_PASS_PLACEHOLDER' ssh user@172.16.42.1
# 或配置 ~/.ssh/config.d/jason.conf 后: ssh jason
```

### WiFi（局域网, 当前不可用 — 见 §7.8）
```bash
sshpass -p 'DEVICE_PASS_PLACEHOLDER' ssh user@192.168.0.93   # 修复后恢复; IP 可能变, 先用 USB 查
```

### Fastboot（维护模式）
```bash
ssh user@172.16.42.1 'sudo reboot bootloader'
# 或关机后按住 音量下 + 电源
fastboot devices
```

---

## 4. 关键操作命令

### 关机（软关机, 非真正断电）
```bash
# 远程执行 safe-poweroff.sh → 设备 halt → 长按电源键 15s+ 物理断电
sshpass -p 'DEVICE_PASS_PLACEHOLDER' ssh user@172.16.42.1 'echo DEVICE_PASS_PLACEHOLDER | sudo -S /usr/local/bin/safe-poweroff.sh'
```

⚠️ **不要用 `sudo poweroff`** — 会导致重启而非关机（详见 §6 poweroff 调查结论）

### 重启
```bash
sshpass -p 'DEVICE_PASS_PLACEHOLDER' ssh user@172.16.42.1 'echo DEVICE_PASS_PLACEHOLDER | sudo -S reboot'
```

### 部署/重刷
```bash
./scripts/deploy.sh --all        # 完整部署 (设备需在 fastboot)
./scripts/deploy.sh --persist     # 持久化 boot 分区 (设备需已启动且 SSH 可达)
./scripts/deploy.sh --verify      # 验证 SSH + cpufreq
```

### 刷回原厂 Android
```bash
cd jason_images_V8.5.9.0.NCHCNED_20170831.0000.00_7.1_cn
./flash_all.sh
# 然后进 TWRP 恢复 modemst1/modemst2/fsg/persist
```

---

## 5. 关键文件索引

### 文档
| 文件 | 用途 |
|------|------|
| [AGENTS.md](./AGENTS.md) | 项目规则/权限/目标 |
| [docs/使用文档.md](./docs/使用文档.md) | 使用文档（连接/运维/性能） |
| [docs/设备状态清单.md](./docs/设备状态清单.md) | 设备完整状态（可复现性基准） |
| [docs/工作进展.md](./docs/工作进展.md) | 完整工作进展记录 |
| [docs/刷机指南.md](./docs/刷机指南.md) | 刷机/回退流程 |
| [docs/故障排查.md](./docs/故障排查.md) | 故障排查（含 WiFi firmware 修复） |
| [docs/快速恢复指南.md](./docs/快速恢复指南.md) | 应急一页纸 |

### 脚本
| 文件 | 用途 |
|------|------|
| [scripts/one-click-restore.sh](./scripts/one-click-restore.sh) | **一键还原**（A-E 场景自动检测, 2026-08-18 实测通过） |
| [scripts/deploy.sh](./scripts/deploy.sh) | 部署/刷入/验证一体化脚本 |
| [scripts/device-full-backup.sh](./scripts/device-full-backup.sh) | 全系统备份（rootfs tar + boot dd, 可重跑刷新快照） |
| [scripts/restore-device-state.sh](./scripts/restore-device-state.sh) | 配置级恢复（脚本+timer+配置） |
| [scripts/modify-bootimg-cmdline.py](./scripts/modify-bootimg-cmdline.py) | boot.img cmdline 修改工具 |
| [scripts/apply-jason-patches.sh](./scripts/apply-jason-patches.sh) | 应用 pmaports 补丁 |
| [scripts/backup-partitions.sh](./scripts/backup-partitions.sh) | 分区备份 |
| [scripts/restore.sh](./scripts/restore.sh) | 恢复 |

### 备份资产（一键还原的数据源）
| 目录 | 内容 |
|------|------|
| [backups/full-system-20260829-fixed/](./backups/full-system-20260829-fixed/) | **当前权威全系统备份 (2026-08-29 修复后基线)**: rootfs.tar.gz (278MB, 含 WiFi 新固件) + boot dd 镜像 + md5 全部通过; 恢复路径见包内 README |
| [backups/full-system-20260818-v2/](./backups/full-system-20260818-v2/) | 旧全系统备份 (18:59, 修复前 r36 基线) — 仅作历史回退层次, 常规恢复勿用 |
| [artifacts/firmware-wcn3990-20260829/](./artifacts/firmware-wcn3990-20260829/) | WiFi 固件三件套归档 (wlanmdsp WLAN.HL.2.0 + board-2 + firmware-5), rootfs 重刷后重装用 |
| [backups/boot-part-20260818-pre-initfs.img](./backups/) | 刷 r36 前的 boot 分区原样备份 (md5 5f1e1887), 回 r35 用 |
| [artifacts/boot-r36-20260818.img](./artifacts/) | r36 boot.img (cmdline 已注入, 即当前 boot 分区内容) |
| [backups/device-state-20260818/](./backups/device-state-20260818/) | 配置级备份（脚本/timer/配置 tar 包） |
| [backups/original-jason-20260627-114354/](./backups/original-jason-20260627-114354/) | 原厂 28 分区镜像 (sha256 28/28 通过) |
| [backups/whyred-non-hlos-20260629/](./backups/whyred-non-hlos-20260629/) | WiFi modem 固件 (whyred NON-HLOS fw 1.0.0.591) |
| [artifacts/boot-ubuntu24-stable-nomodem-20260829.img](./artifacts/) | **当前 boot 分区内容** (md5 aed48765, cmdline 含 modem blacklist) |
| [backups/full-system-20260829-fixed/](./backups/full-system-20260829-fixed/) 内 modem-fw-complete.tar.gz | **完整 modem 固件集** (mba 238256B + mdt + b00-b24 共 25 文件, 从 whyred modem.bin 解析提取), WiFi 攻坚时用 |

### 内核/pmaports
| 文件 | 用途 |
|------|------|
| [refs/jason-pmaports-patches/](./refs/jason-pmaports-patches/) | pmOS 包源（device/kernel/firmware/usb-network） |
| [refs/jason-pmaports-patches/linux-postmarketos-qcom-sdm660/](./refs/jason-pmaports-patches/linux-postmarketos-qcom-sdm660/) | 内核 APKBUILD + config + 8 个补丁 |
| [refs/jason-pmaports-patches/0009-msm-poweroff-scm.patch](./refs/jason-pmaports-patches/0009-msm-poweroff-scm.patch) | poweroff 补丁（v3, 调查后保留） |

### 服务器脚本
| 文件 | 用途 |
|------|------|
| [refs/server-scripts/usr-local-bin/safe-poweroff.sh](./refs/server-scripts/usr-local-bin/safe-poweroff.sh) | **关机脚本**（软关机, halt） |
| [refs/server-scripts/usr-local-bin/health-check.sh](./refs/server-scripts/usr-local-bin/health-check.sh) | 健康检查 r4（电池供电/AP 离线不重启） |
| [refs/server-scripts/usr-local-bin/charge-guard.sh](./refs/server-scripts/usr-local-bin/charge-guard.sh) | 充电磁滞控制 60%/40%（r3, 硬件停充, 需内核 r36+, 见 §7.6） |
| [refs/server-scripts/systemd/](./refs/server-scripts/systemd/) | systemd timer 配置 |
| [refs/server-scripts/README.md](./refs/server-scripts/README.md) | 脚本说明 |

### pmbootstrap 工作目录
- pmaports: `/home/lyl/.local/var/pmbootstrap/cache_git/pmaports/device/testing/linux-postmarketos-qcom-sdm660/`
- 输出: `/home/lyl/.local/var/pmbootstrap/chroot_rootfs_xiaomi-jason/`

---

## 6. poweroff 调查最终结论（重要）

**SDM660 TrustZone 固件不支持软件真正断电**。已测试 4 种内核方案全部失败，均被转为 reset：

| 版本 | pkgrel | 方案 | 结果 |
|------|--------|------|------|
| 原始 | r32 | `writel(0, msm_ps_hold)` 直接写 PS_HOLD | 失败 - reset |
| v1 | r33 | `qcom_scm_io_writel(phys, 0)` SCM 安全通道 | 失败 - reset |
| v2 | r34 | 不注册 POWER_OFF handler，PSCI 接管 | 失败 - reset |
| v3 | r35 | `arm_smccc_smc(0x84000008, ...)` 直接 PSCI SMC | 失败 - reset |

**唯一有效方案**: `safe-poweroff.sh`（禁用 watchdog → `halt -f` → 设备 halt 不重启）
- 这是"软关机"（设备停止运行但不断电），要真正断电需长按电源键 15s+
- **rootfs 重刷后脚本会丢失**，需重新部署（见 §7）

详见 [docs/工作进展.md](./docs/工作进展.md) 末尾章节。

---

## 7. 已知问题与注意事项

### 7.1 rootfs 重刷后脚本丢失（重要）
`pmbootstrap install` + `fastboot flash userdata` 重刷 rootfs 后：
- `/usr/local/bin/` 为空，`safe-poweroff.sh` 丢失
- 11 个 systemd timer + 监控脚本全部丢失
- **恢复方法（一键）**: `./scripts/one-click-restore.sh`（自动检测设备状态, 路径 A 实测 30s 完成恢复）
- 手动部署见 [refs/server-scripts/README.md](./refs/server-scripts/README.md)

一键还原场景对照（详见 [docs/快速恢复指南.md §0.5](./docs/快速恢复指南.md)）：

| 模式 | 场景 | 动作 |
|------|------|------|
| A（自动） | SSH 通, 脚本/配置丢 | restore-device-state.sh |
| A+ | 系统文件坏但 SSH 通 | rsync 全量 rootfs (254MB) |
| B（自动） | SSH 不通, fastboot 通 | fastboot flash boot (dd 镜像) |
| C | boot+rootfs 全坏 | deploy --all + A+ |
| D | WiFi 固件坏 | fastboot flash modem (whyred) |
| E | 回原厂（需输 yes） | flash_all.sh |

### 7.2 rootfs UUID 变化
`pmbootstrap install` 会重新生成 rootfs，UUID 会变，必须用 `deploy.sh --update-uuid` 同步 boot.img cmdline。

### 7.3 cpuidle.off=1
内核 cmdline 参数，禁用 cpuidle 避免已知死锁。不要移除。

### 7.4 WiFi firmware
modem 分区刷入 whyred NON-HLOS.bin（fw 1.0.0.591），非 jason 原厂（原厂 1.0.0.533 与 mainline ath10k_snoc 不兼容）。详见 [故障排查.md §7.4](./docs/故障排查.md)。

### 7.5 PSCI 固件 bug
`psci: [Firmware Bug]: failed to set PC mode: -3` — 影响 CPU idle，但不影响启动。

### 7.6 charge-guard 硬件停充 ✅ 已完成（2026-08-18）
用户需求：电量 ≥60% 停充, ≤40% 恢复充电（保护电池防鼓包）。**已实现并部署**。

**方案**: 内核补丁 `0010-smbx-charge-behaviour.patch` 给 qcom_smbx 驱动新增标准
`POWER_SUPPLY_PROP_CHARGE_BEHAVIOUR` 属性（pkgrel 35→36），userspace 直接:
```sh
echo inhibit-charge > /sys/class/power_supply/pm660-charger/charge_behaviour  # 硬件停充
echo auto           > /sys/class/power_supply/pm660-charger/charge_behaviour  # 恢复充电
```

**关键寄存器操作**（补丁实现, 前人盲点是 CHG_EN_SRC_BIT 前置条件）:
- `CHGR_CFG2(0x1051)` bit7 `CHG_EN_SRC_BIT` 置 1 → 软件控制模式（**必须先设**, 否则 0x1042 写入被硬件忽略, init 序列默认不设此位）
- `CHARGING_ENABLE_CMD(0x1042)` bit0: 1=充电使能, 0=停充

**验证证据**（2026-08-18 17:06-17:35 实测）:
- inhibit 后: `1042=00, 1051=81, 1006=0x47`（低3位=111 DISABLE_CHARGE 状态机 + bit6 CC_SOFT_TERMINATE）
- cap=99% 冻结 22 分钟（若真放电 +300mA 早掉 3%, 若真充电早到 100%）→ 电池净电流≈0, USB 直供系统 — 理想停充行为
- A/B 测试: `auto` 写入 → 1042 恢复 01, 命令通路完好; 1006 仍 DISABLE 是电池已满(4.44V)硬件自身 inhibit, 自洽
- 之前 "44 秒被改回" 的元凶 = 当时仍在跑的旧 charge-guard 服务干扰, timer 停掉后 inhibit 稳定 20+ 分钟
- `current_now`(+300mA 显示)在此平台读数不可信（疑测系统负载电流）, 不作为停充判据

**部署状态**: charge-guard.sh r3 + timer (2min) 已上线, 首次动作已验证
`cap=99% >= 60%, charging STOPPED (hw inhibit, battery care)`

**注意事项**:
- 重刷 rootfs 后模块会回旧版 → 需重新 `pmbootstrap install`（r36 已包含）或手动替换 .ko.zst
- 重启后模块从 initramfs 旧副本加载 → 需 `rmmod qcom_smbx && modprobe qcom_smbx` 从 rootfs 加载新模块（rootfs 上 md5=5cfe139c 为 r36）
- charge-guard r3 有属性存在性守卫: 属性缺失时拒绝运行并记 ERROR 日志

### 7.7 initramfs 固化 qcom_smbx r36 模块 ✅ 已完成（2026-08-18 18:31, 方案 A）

**问题**: initramfs 里曾是 r35 旧模块（无 charge_behaviour）, 重启后 charge-guard 失效需手动 rmmod+modprobe。
**结果**: **已固化, 重启零依赖** — 开机即 r36, charge-guard 2min 内自动接管 (18:31:36 实测 `charging STOPPED (hw inhibit)`)。

**实际执行路径**（与原计划的关键差异）:
1. `pmbootstrap initfs` 直接跑**无效** — rootfs chroot 里装的是旧内核包, initramfs 打包的还是 r35 (24344 字节/srcversion 5B07...)
2. `pmbootstrap install` 会尝试升级上游 7.0.14 内核且网络下载失败, 不可用
3. **正确做法**: apk.static 直装本地 r36 apk 进 chroot, 再 initfs:
```bash
sudo ~/.local/var/pmbootstrap/apk.static --root ~/.local/var/pmbootstrap/chroot_rootfs_xiaomi-jason \
  --repository ~/.local/var/pmbootstrap/packages/edge add --allow-untrusted \
  ~/.local/var/pmbootstrap/packages/edge/aarch64/linux-postmarketos-qcom-sdm660-6.19.10-r36.apk
pmbootstrap initfs && pmbootstrap export
```
4. 验证 initramfs 内模块: 解包 cpio → `modinfo` srcversion 必须 = `66A494BF62A12015D20C5B6` (24808 字节)
5. cmdline 注入: 用**设备现役 /proc/cmdline 的 UUID** (boot=7d83c53d... root=5a0e068c...), 不要信 export 镜像自带的 (它是 debug 版含 pmos.debug-shell)
```bash
python3 scripts/modify-bootimg-cmdline.py /tmp/postmarketOS-export/boot.img /tmp/boot-r36-cmdline.img "<现役完整 cmdline>"
```
6. `fastboot boot` 临时验证 → `deploy.sh --flash-boot` 持久化 (自动备份+MD5+magic 校验+重启)

**验证证据（三重）**:
- fastboot boot 临时启动: charge_behaviour 开箱即在, charge-guard 18:27:09 自动接管
- boot 分区持久化后重启: srcversion=66A494BF 从 boot 分区加载
- 18:31:36 (开机~2min): `cap=99% >= 60%, charging STOPPED (hw inhibit, battery care)` 全自动

**资产**:
- 刷前 boot 分区备份: `backups/boot-part-20260818-pre-initfs.img` (md5 5f1e1887)
- r36 boot.img: `/tmp/boot-r36-cmdline.img` (cmdline 已注入, 23.7MB)

**遗留**: /tmp 下的 boot-r36 镜像重启本机会丢; 若需长期保留复制到 artifacts/

### 7.8 WiFi 固件崩溃循环 ✅ 已修复（2026-08-29 03:14, 固件三件套替换）

**结果**: WiFi 已恢复连接 LYL (10.57.122.140), 修复后 0 次固件崩溃, WiFi SSH 实测通过。

**根因回顾**: 2026-08-18 换路由器后 WCN3990 固件 (WLAN.HL.1.0.1.c2-00538, 2019-07 build) 反复崩溃
(modem remoteproc crash → 6s 精确循环, 8-18 当日 100+ 次), 触发源为新 AP 环境下的老固件 bug。

**修复方案（底层固件替换, rootfs 层可回退）**:
从 linux-firmware 上游仓库下载 WCN3990 三件套替换/补装到 `/lib/firmware/ath10k/WCN3990/hw1.0/`:

| 文件 | 版本 | md5 | 说明 |
|---|---|---|---|
| wlanmdsp.mbn | WLAN.HL.2.0-01387 (新 3.7MB) | 259b4f9e | **主固件**, 原为 modem 分区 2019 版经 tqftpserv 提供 |
| board-2.bin | 上游 board-2 | 420356eb | board 数据 (board_id 匹配), 原缺失 |
| firmware-5.bin | 上游 feature flags | d16e3444 | 原 60B 为旧 flags |

- 原固件备份: 设备 `/var/backups/ath10k-wcn3990-orig/` (board.bin + firmware-5.bin)
- 重载驱动后 dmesg 验证: `features wowlan,mgmt-tx-by-reference,non-bmi crc32 b3d4b790` (新固件特征, 原 31b6f1c6)
- board_id=0 匹配失败走 board.bin fallback, 功能正常

**注意**:
- wlanmdsp 放 rootfs 后 tqftpserv 可能优先提供 modem 分区版本 — dmesg `fw_build` 若回退 1.0.1.c2 说明走了 modem, 需排查 tqftpserv 根目录
- rootfs 重刷会丢固件文件, 需重装 (源文件在主机 `/tmp/wcn3990-fix/` 或重新从 linux-firmware 下载)
- 新 AP 环境的其他 WPA1/WPA2 混合路由器仍是潜在触发源, 但新固件下未复现

### 7.9 时钟错误 13 天 ✅ 已修复（2026-08-29 03:08）

**现象**: 设备时钟停在 2026-08-16 19:17 (真实 08-29 03:08), 慢 13 天; NTP 未同步 (usb0 无网关出口), `systemd-time-wait-sync` timeout failed。

**根因链**（三层断链）:
1. PMIC RTC 只增到 1217s (0 起算), 无真实时间
2. **swclock-offset-save 从未运行** (`not-found`), offset-storage 停在 08-18 手工值 → 开机 swclock-offset-boot 把时间设回 08-16 时代
3. **fake-rtc-restore.service 是 static 未挂 wants** (`-- No entries --`), 断网开机时无人恢复时间; NTP 又因无网关永远同步不了

**修复动作**:
1. 立即 `date -s @<host_ts>` 校正到真实时间 → NTP 随即 `synchronized: yes`
2. 重算 `/var/cache/swclock-offset/offset-storage` = ts - rtc0_since_epoch (1787942593)
3. `ln -sf` fake-rtc-restore.service 进 `multi-user.target.wants/` (脚本自带年份守卫, NTP 正常时不动作)

**遗留**: swclock-offset-save.service `not-found` 需在下次重启前修复 (APKBUILD swclock-offset 包缺失 save 单元), 否则下次关机 offset 又停更; 已有 fake-rtc-save.timer 30min 兜底。

### 7.10 Ubuntu 24.04 移植 — modem/WiFi 搁置 ⚠️（2026-08-29）

**背景**: 用户批准方案 A (pmOS 内核 + Ubuntu 24.04 rootfs, boot.img 与 rootfs 解耦)。安装成功, USB SSH 正常。

**已完成**:
1. 主机组装 userdata-ubuntu.img: GPT (p1 boot ext2 96M `7d83c53d-...` + p2 root ext4 51.2G `5a0e068c-...`), chroot 配置 systemd/ssh/network-manager/chrony/sudo
2. fastboot flash userdata + `fastboot boot` 临时引导验证
3. usb-gadget.service 修复 (幂等版, configfs 不允许覆盖 symlink, 已同步 refs/server-scripts/usr-local-bin/)
4. charge_behaviour 可读 (qcom-battery), chrony/ssh/usb-gadget 全部 active

**WiFi 失败的根因链 (4 次挂死的完整诊断)**:
```
WCN3990 WiFi 固件 (wlanmdsp.mbn) 运行在 modem DSP 上
  → WiFi 依赖 modem (qcom_q6v5_mss remoteproc) 完整启动
  → Ubuntu 上 modem 生态不成熟:
     (a) 首次挂死: modem.b10 固件缺失 (只拷了 b00-b09, whyred 有 b00-b24 共 28 段)
         → modem 半加载失败 → BPF JIT kick_all_cpus_sync 跨 CPU 死锁
     (b) 二次挂死: 固件补齐后, rmtfs -s 自动拉起 modem, 但 diag-router 缺失
         → modem diag 任务饥饿 → 40s 崩溃循环 → RCU stall
     (c) 三次挂死: diag-router 补齐 (pmOS musl 二进制 + ld-musl runner) 后 modem 仍挂死
         → pd-mapper 缺 .jsn PD 描述符 / functionfs 注册异常 (内核 6.19 CONFIG_USB_F_FS=m 但 fs 未注册)
  → 结论: modem 生态在 Ubuntu 上需要大量调试 (pmOS 靠 msm-firmware-loader + soc-qcom-sdm660-rproc 全家桶)
```

**最终决策 (2026-08-29, 用户知情)**: 稳定优先 — **boot.img 永久 blacklist modem**:
- `artifacts/boot-ubuntu24-stable-nomodem-20260829.img` (md5 aed48765) 已 dd 持久化到 boot 分区, cmdline 含 `modprobe.blacklist=qcom_q6v5_mss`
- qrtr-ns/tqftpserv/rmtfs/pd-mapper/diag-router 全部 disable (防误触发)
- 完整重启循环验证通过: USB SSH + 0 failed 单元
- 完整 modem 固件集已提取归档 (见 §5 whyred 提取物), 未来攻坚 WiFi 时可直接用

**WiFi 恢复的两条路径** (未来):
- 路径 1 (推荐): 回 pmOS rootfs (v3 备份一键恢复), pmOS 生态下 WiFi 已修好 (§7.8)
- 路径 2 (攻坚): Ubuntu 下补齐 pd-mapper .jsn 描述符 + functionfs 修复 + msm-firmware-loader 逻辑移植, 工作量数天级

---

## 8. pmbootstrap 工作流

### 更新内核流程
```bash
# 1. 修改补丁
vim /home/lyl/.local/var/pmbootstrap/cache_git/pmaports/device/testing/linux-postmarketos-qcom-sdm660/0009-msm-poweroff-scm.patch

# 2. 修改 APKBUILD (pkgrel +1, 更新 sha512sum)
vim .../APKBUILD

# 3. 编译
pmbootstrap build linux-postmarketos-qcom-sdm660

# 4. 安装 (生成 rootfs 镜像)
pmbootstrap install --password DEVICE_PASS_PLACEHOLDER

# 5. 导出
pmbootstrap export

# 6. 部署 (设备需在 fastboot)
./scripts/deploy.sh --update-uuid
./scripts/deploy.sh --flash-rootfs    # fastboot flash userdata
./scripts/deploy.sh --boot-temp       # fastboot boot (临时启动)
# 等待 60s 设备启动
./scripts/deploy.sh --persist         # dd 写入 boot 分区 (持久化)
./scripts/deploy.sh --verify
```

### 代理（下载资源用）
订阅链接: `PROXY_SUB_URL_PLACEHOLDER`

---

## 9. 最近 git 历史

```
b9bed86 health-check r7: ath10k 重载后 wlan0 未回归(QMI error 90 深卡死)时立即 reboot, 避免白等 30min
5caacd7 health-check r6: ath10k 固件挂死自愈 (rmmod+modprobe, 6次上限回落 reboot); 修正 r5 把驱动挂死误判为环境离线的缺陷
052cf7a WiFi 路由器更换事故处置 + health-check r5 防重启循环
5b48ea5 AGENTS: 密码集中 secrets.env 说明 + 公开仓库发布规则
5b4b527 公开仓库准备: 密码改 secrets.env 机制, 大文件移出 git 历史留本地
d335a43 快速恢复指南: 全部指向 v2 备份 (r36 基线) + 一键还原脚本入口 + 恢复后自检
0f4b43b one-click-restore 指向 v2 备份 (r36 基线); 修 A+ rsync 源路径 (v2 tar 根打包无子目录); 加恢复后自检提示
ec60c49 HANDOVER 备份资产索引指向 v2 权威备份 (r36 基线)
9f6bc6a 全系统备份 v2 (r36 后基线): boot 分区 dd + rootfs tar + 元数据
fe1be3d 方案A完成: initramfs 固化 qcom_smbx r36, 重启零依赖 charge-guard 全自动
2dcff93 HANDOVER §7.7: 新会话执行方案 A (initramfs 固化 qcom_smbx r36) 完整交接步骤
f873c83 charge-guard 硬件停充完成: 内核补丁0010 (r36) + charge_behaviour 属性 + r3 上线
```

---

## 10. 推迟的任务（可选）

1. **swclock-offset-save not-found 修复** — 见 §7.9 遗留, 下次重启前修
2. **WiFi 30min 稳定性观察** — 固件替换后 0 崩溃, 持续观察 `dmesg | grep -c "firmware crashed"`
3. **硬件 watchdog DTS** — 在 sdm660.dtsi 添加 `qcom,apss-wdt` 节点（当前用 softdog 软件看门狗）
4. **USB OTG host 模式** — 需先修复 GPIO 58 上拉
5. **SSH 偶发超时观察** — 2026-08-18 14:33-14:38 出现多次后自愈, 复发查 `journalctl -u sshd`
6. **电池长期保养** — 每月一次 99→30% 放电循环防鼓包（charge-guard r3 已接管磁滞控制）

---

## 11. 快速恢复决策表

| 症状 | 处理 |
|------|------|
| 设备无响应 | 长按电源键 15s+ 强制重启 |
| SSH 连不上 (USB) | 检查 USB 线 / `lsusb` 看 `18d1:d001` / 重启设备 |
| SSH 密码错误 | 用户名是 `user` 不是 `root`; 密码 `DEVICE_PASS_PLACEHOLDER` |
| SSH host key 改变 | `ssh-keygen -R 172.16.42.1` |
| WiFi 崩溃循环 | 已修复见 §7.8 (固件三件套替换); 复发先查 `dmesg | grep -c "firmware crashed"` |
| WiFi 不连接 | `nmcli device wifi connect "泽川源科技" password "$WIFI_CHINANET_PASS" ifname wlan0` (需 sudo) |
| poweroff 变重启 | 用 `safe-poweroff.sh`（见 §4） |
| rootfs 损坏 | `./scripts/one-click-restore.sh`（自动检测; 或 --mode C 重刷） |
| 脚本/timer 丢失 | `./scripts/one-click-restore.sh`（路径 A, 30s 完成） |
| 完全回退原厂 | `./scripts/one-click-restore.sh --mode E`（见 [刷机指南.md](./docs/刷机指南.md)） |

详见 [docs/快速恢复指南.md](./docs/快速恢复指南.md)。

---

## 12. 新对话起点建议

新对话开始时，建议先：

1. **读 [AGENTS.md](./AGENTS.md)** — 了解项目规则和权限
2. **读本文件** — 了解当前状态
3. **🔴 若继续 WiFi 修复任务**: 直接读 §7.8（根因/证据链/两条修复路径/验证命令都已写全）, 然后按用户选择的路径执行
4. **检查设备状态**:
   ```bash
   ping -c 2 172.16.42.1                                    # 设备是否在线
   sshpass -p 'DEVICE_PASS_PLACEHOLDER' ssh user@172.16.42.1 'uname -r; uptime'  # SSH 是否可达
   ```
5. **如果设备离线**: 长按电源键 15s+ 开机，等 60-90s 后重试
6. **根据用户需求** 查阅对应文档

---

**最后更新**: 2026-08-29 03:20 | **git HEAD**: 见 git log | **设备**: 运行中 (USB + WiFi 双通道正常, charge-guard 正常)
