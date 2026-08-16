# 项目交接文档 (Handover)

> 生成日期: 2026-07-02
> 上一会话最后操作: 执行 safe-poweroff.sh 关机, 设备已 halt
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
- **设备状态**: **已 halt（软关机）** — 上一会话执行了 `safe-poweroff.sh`
- **下次开机**: 长按电源键 15s+ 物理重启（软件层面已无法操作）
- **开机后**: 自动进入 Linux（boot 已持久化，无需 fastboot boot）

### 2.2 系统配置
| 项 | 值 |
|---|---|
| 设备 | Xiaomi Mi Note 3 (jason) |
| SoC | Qualcomm SDM660 (8 核: 4×A53 + 4×A73) |
| 内存 | 6 GB |
| 存储 | 128 GB eMMC |
| 系统 | postmarketOS edge (Alpine Linux) |
| 内核 | `6.19.10-sdm660` (r35, #36-postmarketos-qcom-sdm660) |
| 内核特性 | cpufreq-hw + softdog watchdog + msm-poweroff 补丁 (0009) |
| init 系统 | systemd (PID 1 = systemd) |
| USB 连接 | NCM gadget, 设备 IP `172.16.42.1/16` |
| SSH 用户 | `user` (密码 `DEVICE_PASS_PLACEHOLDER`) |
| WiFi | `ChinaNet-810` (密码 `WIFI_CHINANET_PASS_PLACEHOLDER`), DHCP 分配 IP |
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
| [scripts/deploy.sh](./scripts/deploy.sh) | 部署/刷入/验证一体化脚本 |
| [scripts/modify-bootimg-cmdline.py](./scripts/modify-bootimg-cmdline.py) | boot.img cmdline 修改工具 |
| [scripts/apply-jason-patches.sh](./scripts/apply-jason-patches.sh) | 应用 pmaports 补丁 |
| [scripts/backup-partitions.sh](./scripts/backup-partitions.sh) | 分区备份 |
| [scripts/restore.sh](./scripts/restore.sh) | 恢复 |

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
| [refs/server-scripts/usr-local-bin/health-check.sh](./refs/server-scripts/usr-local-bin/health-check.sh) | 健康检查 r3 |
| [refs/server-scripts/systemd/](./refs/server-scripts/systemd/) | 9 个 systemd timer 配置 |
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
- 9 个 systemd timer + 监控脚本全部丢失
- 必须重新部署：

```bash
# 部署 safe-poweroff.sh
sshpass -p 'DEVICE_PASS_PLACEHOLDER' scp refs/server-scripts/usr-local-bin/safe-poweroff.sh user@172.16.42.1:/tmp/
sshpass -p 'DEVICE_PASS_PLACEHOLDER' ssh user@172.16.42.1 'echo DEVICE_PASS_PLACEHOLDER | sudo -S install -m 755 /tmp/safe-poweroff.sh /usr/local/bin/'

# 部署 9 个监控脚本 + timer（如有需要）
# 见 refs/server-scripts/README.md
```

### 7.2 rootfs UUID 变化
`pmbootstrap install` 会重新生成 rootfs，UUID 会变，必须用 `deploy.sh --update-uuid` 同步 boot.img cmdline。

### 7.3 cpuidle.off=1
内核 cmdline 参数，禁用 cpuidle 避免已知死锁。不要移除。

### 7.4 WiFi firmware
modem 分区刷入 whyred NON-HLOS.bin（fw 1.0.0.591），非 jason 原厂（原厂 1.0.0.533 与 mainline ath10k_snoc 不兼容）。详见 [故障排查.md §7.4](./docs/故障排查.md)。

### 7.5 PSCI 固件 bug
`psci: [Firmware Bug]: failed to set PC mode: -3` — 影响 CPU idle，但不影响启动。

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
0c3a6e7 (HEAD -> main) poweroff 调查完成: SDM660 软件断电不可行, safe-poweroff.sh 为最终方案
28012eb feat: add safe-poweroff.sh to halt without softdog reboot
ca083cb docs: poweroff unreliable, use sync + long-press power button
85f9f12 docs(使用文档): add poweroff instructions + slim bluetooth/battery
65982be docs: add 快速恢复指南.md + fix 设备状态清单 UUID/mode
dc83086 docs: add health-check r3 + CPU/memory stress test r2 results
0944f1f feat(health-check): r3 skip wlan0/gateway checks when WiFi radio off
9a947be fix(health-check): r2 split soft/hard failures to stop backpack bootloop
```

---

## 10. 推迟的任务（可选）

1. **硬件 watchdog DTS** — 在 sdm660.dtsi 添加 `qcom,apss-wdt` 节点（当前用 softdog 软件看门狗）
2. **USB OTG host 模式** — 需先修复 GPIO 58 上拉
3. **重新部署 9 个监控脚本** — rootfs 重刷后丢失（health-check/temp-monitor/net-monitor 等 systemd timer）
4. **battery-care 电池保养** — 长期 100% 充电易鼓包，需物理管理 + 软件监控

---

## 11. 快速恢复决策表

| 症状 | 处理 |
|------|------|
| 设备无响应 | 长按电源键 15s+ 强制重启 |
| SSH 连不上 (USB) | 检查 USB 线 / `lsusb` 看 `18d1:d001` / 重启设备 |
| SSH 密码错误 | 用户名是 `user` 不是 `root`; 密码 `DEVICE_PASS_PLACEHOLDER` |
| SSH host key 改变 | `ssh-keygen -R 172.16.42.1` |
| WiFi 不连接 | `nmcli device wifi connect "ChinaNet-810" password "WIFI_CHINANET_PASS_PLACEHOLDER" ifname wlan0` |
| poweroff 变重启 | 用 `safe-poweroff.sh`（见 §4） |
| rootfs 损坏 | `./scripts/deploy.sh --all`（设备需进 fastboot） |
| 完全回退原厂 | `cd jason_images_* && ./flash_all.sh`（见 [刷机指南.md](./docs/刷机指南.md)） |

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

**最后更新**: 2026-07-02 | **git HEAD**: `0c3a6e7` | **设备**: 已 halt（需长按电源键重启）
