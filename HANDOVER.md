# 项目交接文档 (Handover)

> 生成日期: 2026-07-02 | 最后更新: 2026-08-18
> 上一会话最后操作: **全系统备份 v2 入库** (r36 后基线, 备份资产索引已更新指向 v2); 无未完成的进行中任务
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
- **设备状态**: 运行中 (2026-08-18), SSH/WiFi/USB 均正常
- **当前网络**: WiFi `LYL` (密码 `WIFI_LYL_PASS_PLACEHOLDER`) + USB NCM `172.16.42.1`
- **开机后**: 自动进入 Linux（boot 已持久化，无需 fastboot boot）

### 2.2 系统配置
| 项 | 值 |
|---|---|
| 设备 | Xiaomi Mi Note 3 (jason) |
| SoC | Qualcomm SDM660 (8 核: 4×A53 + 4×A73) |
| 内存 | 6 GB |
| 存储 | 128 GB eMMC |
| 系统 | postmarketOS edge (Alpine Linux) |
| 内核 | `6.19.10-sdm660` (r36, #36-postmarketos-qcom-sdm660) |
| 内核特性 | cpufreq-hw + softdog watchdog + msm-poweroff 补丁 (0009) |
| init 系统 | systemd (PID 1 = systemd) |
| USB 连接 | NCM gadget, 设备 IP `172.16.42.1/16` |
| SSH 用户 | `user` (密码 `DEVICE_PASS_PLACEHOLDER`) |
| WiFi | `LYL` (密码 `WIFI_LYL_PASS_PLACEHOLDER`), DHCP 分配 IP |
| 监控体系 | 11 个 systemd timer + 13 个脚本 (见 §5) |
| 电池 | 2026-08-16 放电实测 12h55m (99→20%), 健康度 ~98% |
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

### WiFi（局域网）
```bash
sshpass -p 'DEVICE_PASS_PLACEHOLDER' ssh user@192.168.1.17   # IP 可能变, 先用 USB 查
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
| [backups/full-system-20260818-v2/](./backups/full-system-20260818-v2/) | **当前权威全系统备份 (18:59, r36 后基线)**: rootfs.tar.gz (268MB 零错误) + boot dd 镜像 (r36 已验证) + 元数据; 恢复路径见包内 README |
| [backups/full-system-20260818/](./backups/full-system-20260818/) | 旧全系统备份 (14:05, **r35 基线**) — 仅作历史回退层次, 常规恢复勿用 |
| [backups/boot-part-20260818-pre-initfs.img](./backups/) | 刷 r36 前的 boot 分区原样备份 (md5 5f1e1887), 回 r35 用 |
| [artifacts/boot-r36-20260818.img](./artifacts/) | r36 boot.img (cmdline 已注入, 即当前 boot 分区内容) |
| [backups/device-state-20260818/](./backups/device-state-20260818/) | 配置级备份（脚本/timer/配置 tar 包） |
| [backups/original-jason-20260627-114354/](./backups/original-jason-20260627-114354/) | 原厂 28 分区镜像 (sha256 28/28 通过) |
| [backups/whyred-non-hlos-20260629/](./backups/whyred-non-hlos-20260629/) | WiFi modem 固件 (whyred NON-HLOS fw 1.0.0.591) |

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
76df8bf (HEAD -> main) charge-guard 硬件停充完成: 内核补丁0010 (r36) + charge_behaviour 属性 + r3 上线
2970fb1 HANDOVER.md 全面更新到 2026-08-18: 一键还原 A-E 场景, 备份资产索引, §7.6 charge-guard 调查现状
519accc one-click-restore.sh 一键还原 (A-E 场景自动检测); charge-guard r2 修复停充震荡偷充电 bug; 已实测路径 A
d266e96 快速恢复指南: 新增 0.5 一键还原速查 (A-E 场景, 对接 2026-08-18 全系统备份)
741ed95 修复原厂备份 sha256 清单(补全 15 个缺失条目, 28/28 校验通过)
24a204f 全系统备份: rootfs tar+boot dd+boot 文件+分区元数据, 4 场景恢复文档
1f28a2e charge-guard 磁滞充电控制 (60/40): status 属性可写发现+部署+全量备份+一键恢复脚本
```

---

## 10. 推迟的任务（可选）

1. **硬件 watchdog DTS** — 在 sdm660.dtsi 添加 `qcom,apss-wdt` 节点（当前用 softdog 软件看门狗）
2. **USB OTG host 模式** — 需先修复 GPIO 58 上拉
3. **SSH 偶发超时观察** — 2026-08-18 14:33-14:38 出现多次后自愈, 复发查 `journalctl -u sshd`
4. **电池 40-60% 循环启动** — 当前 cap 冻结 99% (inhibit=USB直供, 电池悬浮); 要进入 40-60 区间需手动拔线放电到 60% 以下再插回, 之后磁滞自动接管
5. **电池长期保养** — 每月一次 99→30% 放电循环防鼓包（charge-guard r3 已接管磁滞控制）

---

## 11. 快速恢复决策表

| 症状 | 处理 |
|------|------|
| 设备无响应 | 长按电源键 15s+ 强制重启 |
| SSH 连不上 (USB) | 检查 USB 线 / `lsusb` 看 `18d1:d001` / 重启设备 |
| SSH 密码错误 | 用户名是 `user` 不是 `root`; 密码 `DEVICE_PASS_PLACEHOLDER` |
| SSH host key 改变 | `ssh-keygen -R 172.16.42.1` |
| WiFi 不连接 | `nmcli device wifi connect "LYL" password "WIFI_LYL_PASS_PLACEHOLDER" ifname wlan0` |
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
3. **检查设备状态**:
   ```bash
   ping -c 2 172.16.42.1                                    # 设备是否在线
   sshpass -p 'DEVICE_PASS_PLACEHOLDER' ssh user@172.16.42.1 'uname -r; uptime'  # SSH 是否可达
   ```
4. **如果设备离线**: 长按电源键 15s+ 开机，等 60-90s 后重试
5. **根据用户需求** 查阅对应文档

---

**最后更新**: 2026-08-18 | **git HEAD**: `519accc` | **设备**: 运行中, 一键还原已就绪
