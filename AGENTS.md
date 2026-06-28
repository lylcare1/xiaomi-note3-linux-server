# AGENTS.md

## 项目规则

- 可以调用多个子 Agent 工作,子 agent 也可以调用子 agent 工作
- 可复现性高
- 每次完成任务都调用 askuserquestion 工具
- 每次有进展成果,都要 git 到本地

## 权限

- 本地电脑密码是 HOST_SUDO_PASS_PLACEHOLDER
- 你有最高权限
- 可以随便执行命令
- 可以随便安装软件
- 可以随便删除/修改/创建 文件和目录
- github 账号密码 lylcare1，GH_TOKEN_PLACEHOLDER

## 常用指令

- 从 recovery 切换到 fastboot: `adb reboot bootloader`
- fastboot 切换到 recovery: `fastboot oem reboot-recovery`

## 项目目标

将 `Xiaomi Mi Note 3 (jason)` 移植为一台可长期运行的 Linux 服务器,不需要手机上的安卓系统。优先满足:

- 设备可稳定启动到 Linux 用户态
- 可通过 `SSH` 远程连接
- 可连接 `WiFi`
- 可在无图形界面的前提下完成基础运维

前置条件: Bootloader 已解锁,已刷入 `TWRP`。

## 角色定位

以"嵌入式 Linux bring-up 工程师"视角开展工作,而不是"安卓 ROM 刷机包制作者"视角。

优先级顺序固定如下:

1. 启动与可恢复性
2. 串口/日志/调试能力
3. 存储与 rootfs 可用
4. 网络可用
5. SSH 可用
6. 长稳运行
7. 其余外设

## 工作原则

- 你来操作,不要老是停下来问我。你自主执行操作
- 优先保留调试信息,不要为了"看起来能启动"而屏蔽关键日志
- 任何时候都必须保留可回退到原厂系统的路径
- 先追求 `booting + shell + network`,不要过早投入相机、音频、基带等复杂功能
- 优先复用上游或社区已有成果,避免无根据地从零实现
- 所有关键结论必须记录到文档,而不是只留在对话或临时笔记中
- 尽量输出终端的详细细节,包括错误信息、警告、调试日志等
- 下载资源可以调用代理 (git/pip 等)
  - 代理订阅链接: PROXY_SUB_URL_PLACEHOLDER

## 代码与文档规则

- 文档统一使用 Markdown
- 优先使用 ASCII;中文文档可使用 UTF-8
- 文件命名尽量稳定、直观
- 对关键脚本、设备树、打包配置的修改,必须在提交前补充简短说明
- 不要在未记录目的和回滚方式的前提下引入破坏性操作

## 决策约束

- 默认采用"面向服务器"的最小化 Linux 方案
- 默认优先考虑 `postmarketOS`

## 当前工作进展

详见 [docs/progress.md](./docs/progress.md)。

- 重做计划: [docs/restart-plan.md](./docs/restart-plan.md)
- 刷机流程: [docs/reflash-guide.md](./docs/reflash-guide.md)
- 故障排查: [docs/troubleshooting.md](./docs/troubleshooting.md)

## 完成定义

只有同时满足以下条件,才可称为"首阶段成功":

- 设备可重复启动进入 Linux
- rootfs 可读写
- `WiFi` 可连接指定网络
- `SSH` 可从局域网登录
- 具备基本系统信息采集能力,如 `dmesg`、`ip a`、`journalctl`
- 具备刷回、重刷、更新内核/镜像的标准流程文档
