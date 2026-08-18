# AGENTS.md — XiaoMiNote3 项目 Agent 接入守则

> **项目根目录**: `/home/lyl/Documents/system/XiaoMiNote3`
> **设备**: Xiaomi Mi Note 3 (jason, SDM660) → 无头 Linux 服务器
> **最后更新**: 2026-07-02

---

## 一、强制规则

### 1. 开聊前 → 先了解上下文

收到用户消息后，第一个动作**必须**是阅读以下文件建立背景：

```
1. 本文件 (AGENTS.md) — 项目规则与权限
2. HANDOVER.md — 项目交接文档（当前状态、关键命令、已知问题）
3. docs/工作进展.md 末尾章节 — 最近完成的工作
```

- 涉及具体历史/决策 → 查 [docs/工作进展.md](./docs/工作进展.md)
- 涉及设备状态 → 查 [docs/设备状态清单.md](./docs/设备状态清单.md)
- 涉及故障排查 → 查 [docs/故障排查.md](./docs/故障排查.md)
- **未了解上下文不得直接操作设备**

### 2. 操作设备前 → 先检查状态

任何涉及设备的操作前，**必须**先确认设备在线：

```bash
ping -c 2 -W 2 172.16.42.1
sshpass -p 'DEVICE_PASS_PLACEHOLDER' ssh -o ConnectTimeout=5 -o PreferredAuthentications=password -o PubkeyAuthentication=no user@172.16.42.1 'uname -r; uptime'
```

- 设备离线 → 提示用户长按电源键 15s+ 重启，等 60-90s 后重试
- SSH 密钥冲突 → `ssh-keygen -R 172.16.42.1`
- **不要在未确认设备状态时执行破坏性操作（fastboot/重刷）**

### 3. 每次完成任务 → 调用 askuserquestion

- 每次完成任务都调用 `askuserquestion` 工具通知用户
- 用户手动终止中断任务时，也调用 `askuserquestion` 确认下一步

### 4. 每次有进展 → git 到本地

```bash
cd /home/lyl/Documents/system/XiaoMiNote3
git add -A && git commit -m "简短说明"
```

- 关键结论、脚本修改、文档更新都要 commit
- 不要等大量变更堆积才提交

---

## 二、项目目标

将 `Xiaomi Mi Note 3 (jason)` 移植为可长期运行的 Linux 服务器，不需要安卓系统。

**首阶段成功定义**（✅ 已达成）：
- 设备可重复启动进入 Linux
- rootfs 可读写
- WiFi 可连接指定网络
- SSH 可从局域网/USB 登录
- 具备 dmesg / ip a / journalctl 能力
- 具备刷回/重刷/更新内核的标准流程文档

**当前阶段**：长稳运行 + 运维完善

### 优先级顺序（固定）

1. 启动与可恢复性
2. 串口/日志/调试能力
3. 存储与 rootfs 可用
4. 网络可用
5. SSH 可用
6. 长稳运行
7. 其余外设

### 角色定位

以"嵌入式 Linux bring-up 工程师"视角开展工作，不是"安卓 ROM 刷机包制作者"。
先追求 `booting + shell + network`，不要过早投入相机、音频、基带等复杂功能。

---

## 三、设备当前状态

| 项 | 值 |
|---|---|
| 内核 | `6.19.10-sdm660` (r35, #36-postmarketos-qcom-sdm660) |
| 系统 | postmarketOS edge (Alpine Linux), systemd |
| USB 连接 | NCM, 设备 IP `172.16.42.1/16` |
| SSH | `user@172.16.42.1`, 密码 `DEVICE_PASS_PLACEHOLDER` |
| WiFi | `ChinaNet-810` (密码 `WIFI_CHINANET_PASS_PLACEHOLDER`) |
| Bootloader | unlocked, boot 已持久化（开机即 Linux） |

详见 [HANDOVER.md](./HANDOVER.md) 和 [docs/设备状态清单.md](./docs/设备状态清单.md)。

---

## 四、关键约束（重要）

### 4.1 关机 — 必须用 safe-poweroff.sh

⚠️ **不要用 `sudo poweroff`** — 会导致重启而非关机！

**根因**：SDM660 TrustZone 固件不支持软件断电，所有 poweroff 路径（writel/SCM/PSCI/直接 SMC）均被转为 reset。已测试 4 种内核方案全部失败。

**正确关机方法**：
```bash
sshpass -p 'DEVICE_PASS_PLACEHOLDER' ssh user@172.16.42.1 'echo DEVICE_PASS_PLACEHOLDER | sudo -S /usr/local/bin/safe-poweroff.sh'
# 设备 halt 后, 长按电源键 15s+ 物理断电
```

### 4.2 rootfs 重刷后脚本丢失

`pmbootstrap install` + `fastboot flash userdata` 重刷 rootfs 后：
- `/usr/local/bin/` 为空，`safe-poweroff.sh` 丢失
- 9 个 systemd timer + 监控脚本全部丢失
- **必须重新部署**（见 [HANDOVER.md §7.1](./HANDOVER.md)）

### 4.3 rootfs UUID 变化

`pmbootstrap install` 会重新生成 rootfs，UUID 会变，必须用 `deploy.sh --update-uuid` 同步 boot.img cmdline。

### 4.4 cpuidle.off=1

内核 cmdline 参数，禁用 cpuidle 避免已知死锁。**不要移除**。

### 4.5 WiFi firmware

modem 分区刷入 whyred NON-HLOS.bin（fw 1.0.0.591），非 jason 原厂。不要刷回原厂 modem。

### 4.6 可回退路径

任何时候都必须保留可回退到原厂系统的路径。原厂备份在 `backups/original-jason-20260627-114354/`。

---

## 五、常用命令

### 连接设备
```bash
sshpass -p 'DEVICE_PASS_PLACEHOLDER' ssh -o PreferredAuthentications=password -o PubkeyAuthentication=no user@172.16.42.1
```

### 重启 / 关机
```bash
# 重启
sshpass -p 'DEVICE_PASS_PLACEHOLDER' ssh user@172.16.42.1 'echo DEVICE_PASS_PLACEHOLDER | sudo -S reboot'

# 关机 (软关机, halt)
sshpass -p 'DEVICE_PASS_PLACEHOLDER' ssh user@172.16.42.1 'echo DEVICE_PASS_PLACEHOLDER | sudo -S /usr/local/bin/safe-poweroff.sh'

# 进入 fastboot
sshpass -p 'DEVICE_PASS_PLACEHOLDER' ssh user@172.16.42.1 'echo DEVICE_PASS_PLACEHOLDER | sudo -S reboot bootloader'
```

### 部署
```bash
./scripts/deploy.sh --all        # 完整部署 (设备需在 fastboot)
./scripts/deploy.sh --persist     # 持久化 boot (设备需已启动)
./scripts/deploy.sh --verify      # 验证 SSH + cpufreq
```

### 刷机模式切换
- TWRP → fastboot: `adb reboot bootloader`
- fastboot → TWRP: `fastboot oem reboot-recovery`
- Linux → fastboot: `sudo reboot bootloader`

---

## 六、工作原则

- **你来操作，不要老是停下来问我**。自主执行操作
- 优先保留调试信息，不要为了"看起来能启动"而屏蔽关键日志
- 先追求 `booting + shell + network`，不要过早投入复杂功能
- 优先复用上游或社区已有成果，避免无根据地从零实现
- 所有关键结论必须记录到文档，而不是只留在对话中
- 尽量输出终端的详细细节，包括错误信息、警告、调试日志
- 如果需要，可以调用多个 Sub Coding Agent 并行工作
- 可复现性高

---

## 七、代码与文档规则

- 文档统一使用 Markdown
- 优先使用 ASCII；中文文档可使用 UTF-8
- 文件命名尽量稳定、直观
- 对关键脚本、设备树、打包配置的修改，必须在提交前补充简短说明
- 不要在未记录目的和回滚方式的前提下引入破坏性操作
- 默认采用"面向服务器"的最小化 Linux 方案
- 默认优先考虑 `postmarketOS`

---

## 八、目录约定

| 路径 | 内容 |
|---|---|
| `AGENTS.md` | 本文件（项目规则） |
| `HANDOVER.md` | 项目交接文档（新对话先读这个） |
| `docs/` | 所有文档（使用文档/状态清单/工作进展/刷机指南/故障排查/快速恢复） |
| `scripts/` | 部署/刷机/备份/恢复脚本 |
| `refs/` | 参考资料（pmaports 补丁/服务器脚本/DTS/initramfs） |
| `artifacts/` | 备份资产（boot/rootfs 镜像） |
| `backups/` | 原厂分区备份 |
| `jason_images_*` | 原厂 fastboot 包 |

---

## 九、关键文件索引

| 文件 | 用途 |
|---|---|
| [HANDOVER.md](./HANDOVER.md) | **新对话先读这个** — 项目全貌交接 |
| [docs/使用文档.md](./docs/使用文档.md) | 连接/运维/性能参考 |
| [docs/设备状态清单.md](./docs/设备状态清单.md) | 设备完整状态（可复现性基准） |
| [docs/工作进展.md](./docs/工作进展.md) | 完整工作进展记录 |
| [docs/刷机指南.md](./docs/刷机指南.md) | 刷机/回退流程 |
| [docs/故障排查.md](./docs/故障排查.md) | 故障排查（含 WiFi firmware 修复） |
| [docs/快速恢复指南.md](./docs/快速恢复指南.md) | 应急一页纸 |
| [scripts/deploy.sh](./scripts/deploy.sh) | 部署/刷入/验证一体化脚本 |
| [refs/server-scripts/usr-local-bin/safe-poweroff.sh](./refs/server-scripts/usr-local-bin/safe-poweroff.sh) | 关机脚本（软关机） |

---

## 十、权限

agent 拥有最高权限：
- **所有密码已集中到 `secrets.env`（根目录, gitignore 不入库, 已在 .gitignore）**
- 查真实值: `cat secrets.env` 或 `source secrets.env`
- 文档/脚本中的 `*_PLACEHOLDER` 均对应 secrets.env 里的同名变量（如 DEVICE_PASS_PLACEHOLDER ↔ DEVICE_PASS）
- 可以自由执行命令、安装软件、增删改文件与目录

### 仓库发布注意（2026-08-18 起生效）

- GitHub 仓库: https://github.com/lylcare1/xiaomi-note3-linux-server （**公开**）
- 历史已 git filter-repo 清洗: 密码→占位符, 大文件（备份镜像/分区 img）移出 git **但保留本地磁盘**
- **禁止**把 secrets.env / backups/*.img / artifacts/*.img 提交进 git（.gitignore 已配置, 勿移除）
- 新脚本一律从 secrets.env 读密码, 不要硬编码

---

## 十一、快速恢复决策表

| 症状 | 处理 |
|---|---|
| 设备无响应 | 长按电源键 15s+ 强制重启 |
| SSH 连不上 (USB) | 检查 USB 线 / `lsusb` 看 `18d1:d001` / 重启设备 |
| SSH 密码错误 | 用户名是 `user` 不是 `root`; 密码 `DEVICE_PASS_PLACEHOLDER` |
| SSH host key 改变 | `ssh-keygen -R 172.16.42.1` |
| WiFi 不连接 | `nmcli device wifi connect "ChinaNet-810" password "WIFI_CHINANET_PASS_PLACEHOLDER" ifname wlan0` |
| poweroff 变重启 | 用 `safe-poweroff.sh`（见 §四 4.1） |
| rootfs 损坏 | `./scripts/deploy.sh --all`（设备需进 fastboot） |
| 完全回退原厂 | `cd jason_images_* && ./flash_all.sh`（见 [刷机指南.md](./docs/刷机指南.md)） |

详见 [docs/快速恢复指南.md](./docs/快速恢复指南.md)。
