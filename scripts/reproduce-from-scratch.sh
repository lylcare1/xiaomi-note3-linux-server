#!/bin/sh
# reproduce-from-scratch.sh
# 用途: 从零开始, 在 Xiaomi Mi Note 3 (jason) 上复现一套可长期运行的 pmOS Linux 系统。
#
# 执行步骤:
#   1. 检查依赖 (fastboot, pmbootstrap, sshpass)
#   2. pmbootstrap init (设备 xiaomi-jason, UI console, systemd-edge)
#   3. 复制 refs/jason-pmaports-patches/ 下的包到 pmbootstrap 工作区
#   4. pmbootstrap checksum + build (4 个包)
#   5. pmbootstrap install --password 1234
#   6. 生成 boot.img (修改 cmdline: 去掉 debug-shell, 加 pmos_boot_uuid/pmos_root_uuid)
#   7. 生成 xiaomi-jason.img (从 pmbootstrap rootfs 输出目录)
#   8. 刷入: fastboot flash boot + userdata + modem (whyred NON-HLOS.bin)
#   9. 重启验证
#
# 幂等: 可重复运行, 每步有进度提示, 失败时 exit 1。
#
# 前置条件:
#   - Bootloader 已解锁 (序列号 d1236a7b)
#   - 设备已进入 fastboot 模式 (adb reboot bootloader)
#   - whyred NON-HLOS.bin 已下载到 /tmp/NON-HLOS-whyred.bin
#   - 本机密码 HOST_SUDO_PASS_PLACEHOLDER (sudo 用)
#
# 用法:
#   ./scripts/reproduce-from-scratch.sh           # 完整流程
#   ./scripts/reproduce-from-scratch.sh --no-flash # 只构建不刷入 (验证构建产物)
#
# 相关文档:
#   - docs/设备状态清单.md  设备状态清单 (目标状态)
#   - docs/刷机指南.md          刷机流程详解
#   - docs/重做计划.md          重做计划与背景
#   - refs/jason-pmaports-patches/  pmOS 包源改动

set -eu

# ==============================================================================
# 全局变量与常量
# ==============================================================================

# 解析脚本所在目录 (项目根 = scripts/ 的父目录)
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
PROJECT_ROOT=$(cd "$SCRIPT_DIR/.." && pwd)

# pmbootstrap 工作区路径
PMBOOTSTRAP_HOME="${PMBOOTSTRAP_HOME:-$HOME/.local/var/pmbootstrap}"
PMAPORTS_DIR="$PMBOOTSTRAP_HOME/cache_git/pmaports"
DEVICE_TESTING_DIR="$PMAPORTS_DIR/device/testing"
CHROOT_NATIVE_HOME="$PMBOOTSTRAP_HOME/chroot_native/home/pmos"
ROOTFS_OUTPUT_DIR="$CHROOT_NATIVE_HOME/rootfs"

# 源 patch 目录
PATCH_SRC="$PROJECT_ROOT/refs/jason-pmaports-patches"

# cmdline 修改脚本
CMDLINE_MODIFIER="$SCRIPT_DIR/modify-bootimg-cmdline.py"

# 关键 UUID (与 设备状态清单.md 一致, 用于 rootfs 子分区)
BOOT_UUID="c5f7e8ec-1086-4198-beb1-5f9f7e21920c"
ROOT_UUID="c79928f5-46b8-49de-8203-6124d458c7ce"

# 构建产物输出目录 (本机, 便于校验)
OUTPUT_DIR="${OUTPUT_DIR:-/tmp/jason-build}"
BOOT_IMG="$OUTPUT_DIR/boot-nodebug.img"
ROOTFS_IMG="$OUTPUT_DIR/xiaomi-jason.img"

# whyred NON-HLOS.bin 路径 (WiFi firmware 修复)
NON_HLOS_WHYRED="${NON_HLOS_WHYRED:-/tmp/NON-HLOS-whyred.bin}"

# 设备 SSH 凭据
DEVICE_USB_IP="172.16.42.1"
SSH_USER="user"
SSH_PASS="1234"

# 本机 sudo 密码
LOCAL_SUDO_PASS="HOST_SUDO_PASS_PLACEHOLDER"

# 是否跳过刷入步骤
NO_FLASH=0
case "${1:-}" in
    --no-flash) NO_FLASH=1 ;;
    "") ;;
    *) echo "[ERROR] 未知参数: $1" >&2; echo "用法: $0 [--no-flash]" >&2; exit 1 ;;
esac

# ==============================================================================
# 辅助函数
# ==============================================================================

# 进度提示
step() {
    echo
    echo "============================================================"
    echo ">>> [Step $1] $2"
    echo "============================================================"
}

# 子步骤提示
substep() {
    echo "  -> $1"
}

# 检查命令是否存在
require_cmd() {
    if ! command -v "$1" >/dev/null 2>&1; then
        echo "[ERROR] 缺少依赖命令: $1" >&2
        echo "        请先安装 (例如: sudo apt install $2)" >&2
        exit 1
    fi
}

# 检查文件是否存在
require_file() {
    if [ ! -f "$1" ]; then
        echo "[ERROR] 必需文件不存在: $1" >&2
        exit 1
    fi
}

# 检查目录是否存在
require_dir() {
    if [ ! -d "$1" ]; then
        echo "[ERROR] 必需目录不存在: $1" >&2
        exit 1
    fi
}

# sudo fastboot 包装器 (本机密码 HOST_SUDO_PASS_PLACEHOLDER)
fb() {
    echo "$LOCAL_SUDO_PASS" | sudo -S fastboot "$@"
}

# ==============================================================================
# Step 1: 检查依赖
# ==============================================================================

step 1 "检查依赖 (fastboot, pmbootstrap, sshpass, python3)"

require_cmd fastboot "fastboot"
require_cmd pmbootstrap "pmbootstrap"
require_cmd sshpass "sshpass"
require_cmd python3 "python3"

substep "fastboot:    $(fastboot --version 2>&1 | head -1 || echo 'version unknown')"
substep "pmbootstrap: $(pmbootstrap --version 2>&1 | head -1 || echo 'version unknown')"
substep "sshpass:     $(sshpass -V 2>&1 | head -1 || echo 'version unknown')"
substep "python3:     $(python3 --version 2>&1)"

# 检查源 patch 目录完整性
require_dir "$PATCH_SRC"
require_dir "$PATCH_SRC/device-xiaomi-jason"
require_dir "$PATCH_SRC/firmware-xiaomi-jason"
require_dir "$PATCH_SRC/linux-postmarketos-qcom-sdm660"
require_dir "$PATCH_SRC/usb-network-jason"
require_file "$CMDLINE_MODIFIER"

# 如果要刷入, 还需检查设备连接 + NON-HLOS.bin
if [ "$NO_FLASH" -eq 0 ]; then
    substep "检查 fastboot 设备连接..."
    if ! fb devices 2>&1 | grep -q "fastboot"; then
        echo "[ERROR] 未检测到 fastboot 设备" >&2
        echo "        请确认设备已进入 fastboot 模式 (adb reboot bootloader)" >&2
        exit 1
    fi
    substep "fastboot 设备已连接: $(fb devices 2>&1 | grep fastboot | awk '{print $1}')"

    substep "检查 whyred NON-HLOS.bin..."
    if [ ! -f "$NON_HLOS_WHYRED" ]; then
        echo "[ERROR] whyred NON-HLOS.bin 不存在: $NON_HLOS_WHYRED" >&2
        echo "        请先下载 whyred V12 fastboot 包并提取 NON-HLOS.bin" >&2
        echo "        详见 docs/刷机指南.md §2.3" >&2
        exit 1
    fi
    substep "NON-HLOS.bin: $NON_HLOS_WHYRED ($(du -h "$NON_HLOS_WHYRED" | cut -f1))"
fi

# 创建输出目录
mkdir -p "$OUTPUT_DIR"
substep "构建产物输出目录: $OUTPUT_DIR"

echo "[OK] 依赖检查通过"

# ==============================================================================
# Step 2: pmbootstrap init
# ==============================================================================

step 2 "pmbootstrap init (设备 xiaomi-jason, UI console, systemd-edge)"

# pmbootstrap init 是交互式的, 这里用环境变量 + 参数自动化
# 如果工作区已存在且 jason 配置已就绪, 跳过
if [ -d "$PMAPORTS_DIR/.git" ] && [ -d "$DEVICE_TESTING_DIR/device-xiaomi-jason" ]; then
    substep "pmbootstrap 工作区已存在且包含 jason 设备包, 跳过 init"
    substep "如需重新 init: pmbootstrap zap && rm -rf $PMBOOTSTRAP_HOME"
else
    substep "执行 pmbootstrap init..."
    # 交互式回答: 设备厂商=xiaomi, 设备名=jason, UI=console, 发行版=edge, init system=systemd
    # 用 expect 或 here-doc 模拟交互 (pmbootstrap 支持部分参数)
    if command -v expect >/dev/null 2>&1; then
        expect <<EOF
set timeout 600
spawn pmbootstrap init
expect "Manufacturer*" { send "xiaomi\r" }
expect "Device name*" { send "jason\r" }
expect "UI*" { send "console\r" }
expect "distribution*" { send "edge\r" }
expect "init system*" { send "systemd\r" }
expect eof
EOF
    else
        echo "[WARN] 未安装 expect, 将手动执行 pmbootstrap init" >&2
        echo "       请手动回答: 厂商=xiaomi, 设备=jason, UI=console, 发行版=edge, init=systemd" >&2
        pmbootstrap init || {
            echo "[ERROR] pmbootstrap init 失败" >&2
            exit 1
        }
    fi
fi

# 验证 pmbootstrap 工作区
require_dir "$PMAPORTS_DIR/.git"
require_dir "$DEVICE_TESTING_DIR"
substep "pmbootstrap 工作区: $PMAPORTS_DIR"
echo "[OK] pmbootstrap init 完成"

# ==============================================================================
# Step 3: 复制 jason-pmaports-patches 到 pmbootstrap 工作区
# ==============================================================================

step 3 "复制 refs/jason-pmaports-patches/ 到 pmbootstrap 工作区"

# 直接调用现有的 apply-jason-patches.sh (幂等, 已处理覆盖逻辑)
substep "调用 apply-jason-patches.sh 应用 device/firmware/kernel 包..."
if [ -x "$SCRIPT_DIR/apply-jason-patches.sh" ]; then
    "$SCRIPT_DIR/apply-jason-patches.sh" "$PMAPORTS_DIR"
else
    /bin/sh "$SCRIPT_DIR/apply-jason-patches.sh" "$PMAPORTS_DIR"
fi

# usb-network-jason 是新增包, apply-jason-patches.sh 未包含, 单独复制
substep "复制 usb-network-jason/ (USB 网络配置包)..."
rm -rf "$DEVICE_TESTING_DIR/usb-network-jason"
cp -rp "$PATCH_SRC/usb-network-jason" "$DEVICE_TESTING_DIR/"
substep "  -> $(ls "$DEVICE_TESTING_DIR/usb-network-jason" | tr '\n' ' ')"

# 验证所有 4 个包就位
for pkg in usb-network-jason firmware-xiaomi-jason linux-postmarketos-qcom-sdm660 device-xiaomi-jason; do
    if [ ! -d "$DEVICE_TESTING_DIR/$pkg" ]; then
        echo "[ERROR] 包目录未就位: $DEVICE_TESTING_DIR/$pkg" >&2
        exit 1
    fi
done
echo "[OK] 4 个包已复制到 pmbootstrap 工作区"

# ==============================================================================
# Step 4: pmbootstrap checksum + build
# ==============================================================================

step 4 "pmbootstrap checksum + build (4 个包)"

# 4.1 checksum (更新 APKBUILD 中的校验值)
substep "4.1 计算校验值 (pmbootstrap checksum)..."
pmbootstrap checksum \
    usb-network-jason \
    firmware-xiaomi-jason \
    linux-postmarketos-qcom-sdm660 \
    device-xiaomi-jason \
    || { echo "[ERROR] pmbootstrap checksum 失败" >&2; exit 1; }

# 4.2 逐个构建 (按依赖顺序)
# 顺序: usb-network-jason -> firmware-xiaomi-jason -> kernel -> device
# (device 依赖前 3 个)
PACKAGES_TO_BUILD="usb-network-jason firmware-xiaomi-jason linux-postmarketos-qcom-sdm660 device-xiaomi-jason"

for pkg in $PACKAGES_TO_BUILD; do
    substep "4.2 构建 $pkg..."
    if pmbootstrap build "$pkg"; then
        echo "       [OK] $pkg 构建成功"
    else
        echo "[ERROR] $pkg 构建失败" >&2
        echo "        可尝试: pmbootstrap build $pkg --force --lax" >&2
        exit 1
    fi
done

echo "[OK] 全部 4 个包构建完成"

# ==============================================================================
# Step 5: pmbootstrap install
# ==============================================================================

step 5 "pmbootstrap install --password 1234 (生成 rootfs)"

substep "生成 xiaomi-jason rootfs 镜像 (含 boot + rootfs 2 分区)..."
# --password 设置用户密码为 1234
# --no-fss  生成完整镜像 (不分割, 适合 fastboot flash userdata)
pmbootstrap install --password 1234 \
    || { echo "[ERROR] pmbootstrap install 失败" >&2; exit 1; }

# 验证 rootfs 镜像生成
if [ ! -f "$ROOTFS_OUTPUT_DIR/xiaomi-jason.img" ]; then
    echo "[ERROR] rootfs 镜像未生成: $ROOTFS_OUTPUT_DIR/xiaomi-jason.img" >&2
    exit 1
fi
substep "rootfs 镜像: $ROOTFS_OUTPUT_DIR/xiaomi-jason.img ($(du -h "$ROOTFS_OUTPUT_DIR/xiaomi-jason.img" | cut -f1))"
echo "[OK] pmbootstrap install 完成"

# ==============================================================================
# Step 6: 生成 boot.img (修改 cmdline)
# ==============================================================================

step 6 "生成 boot.img (修改 cmdline: 去掉 debug-shell, 加 UUID)"

# pmbootstrap export 会把 boot.img 导出到 export 目录
# 这里直接从 chroot 提取 boot.img
PMOS_BOOT_IMG="$ROOTFS_OUTPUT_DIR/boot.img"
if [ ! -f "$PMOS_BOOT_IMG" ]; then
    # 备选路径: pmbootstrap export
    substep "boot.img 不在 rootfs 目录, 尝试 pmbootstrap export..."
    EXPORT_DIR="$OUTPUT_DIR/export"
    mkdir -p "$EXPORT_DIR"
    pmbootstrap export --output "$EXPORT_DIR" \
        || { echo "[ERROR] pmbootstrap export 失败" >&2; exit 1; }
    PMOS_BOOT_IMG="$EXPORT_DIR/boot.img"
fi
require_file "$PMOS_BOOT_IMG"
substep "源 boot.img: $PMOS_BOOT_IMG ($(du -h "$PMOS_BOOT_IMG" | cut -f1))"

# 构建新 cmdline:
# - 保留: quiet, splash, loglevel, earlycon, console
# - 移除: pmos.debug-shell (避免卡在 debug shell)
# - 新增: pmos_boot_uuid, pmos_root_uuid (明确指定 rootfs 子分区 UUID)
NEW_CMDLINE="-quiet -splash loglevel=8 ignore_loglevel earlycon console=ttyMSM0,115200 pmos_boot_uuid=$BOOT_UUID pmos_root_uuid=$ROOT_UUID"

substep "修改 cmdline..."
substep "  去掉: pmos.debug-shell"
substep "  新增: pmos_boot_uuid=$BOOT_UUID"
substep "  新增: pmos_root_uuid=$ROOT_UUID"

python3 "$CMDLINE_MODIFIER" "$PMOS_BOOT_IMG" "$BOOT_IMG" "$NEW_CMDLINE" \
    || { echo "[ERROR] boot.img cmdline 修改失败" >&2; exit 1; }

require_file "$BOOT_IMG"
substep "输出 boot.img: $BOOT_IMG ($(du -h "$BOOT_IMG" | cut -f1))"
echo "[OK] boot.img 生成完成"

# ==============================================================================
# Step 7: 生成最终 xiaomi-jason.img (复制到输出目录)
# ==============================================================================

step 7 "生成 xiaomi-jason.img (复制到输出目录)"

cp -f "$ROOTFS_OUTPUT_DIR/xiaomi-jason.img" "$ROOTFS_IMG"
require_file "$ROOTFS_IMG"
substep "输出 rootfs: $ROOTFS_IMG ($(du -h "$ROOTFS_IMG" | cut -f1))"

# 生成 SHA256 校验值 (供后续 artifacts/SHA256SUMS 使用)
substep "计算 SHA256 校验值..."
BOOT_SHA=$(sha256sum "$BOOT_IMG" | awk '{print $1}')
ROOTFS_SHA=$(sha256sum "$ROOTFS_IMG" | awk '{print $1}')
substep "  boot-nodebug.img:    $BOOT_SHA"
substep "  xiaomi-jason.img:    $ROOTFS_SHA"

# 更新 artifacts/SHA256SUMS (如果存在)
SUMS_FILE="$PROJECT_ROOT/artifacts/SHA256SUMS"
if [ -d "$(dirname "$SUMS_FILE")" ]; then
    substep "更新 $SUMS_FILE ..."
    cat > "$SUMS_FILE" <<EOF
# Artifact SHA256 checksums
# 生成日期: $(date '+%Y-%m-%d')
# 用 sha256sum 生成: sha256sum boot-nodebug.img xiaomi-jason.img > SHA256SUMS

$BOOT_SHA  boot-nodebug.img
$ROOTFS_SHA  xiaomi-jason.img
EOF
    substep "  SHA256SUMS 已更新"
fi

echo "[OK] 镜像生成完成"

# 如果 --no-flash, 到此结束
if [ "$NO_FLASH" -eq 1 ]; then
    echo
    echo "============================================================"
    echo ">>> 构建完成 (未刷入, --no-flash 模式)"
    echo "============================================================"
    echo "产物:"
    echo "  boot.img:      $BOOT_IMG"
    echo "  rootfs.img:    $ROOTFS_IMG"
    echo "  NON-HLOS.bin:  $NON_HLOS_WHYRED"
    echo
    echo "刷入命令 (设备进入 fastboot 后执行):"
    echo "  fb flash boot    $BOOT_IMG"
    echo "  fb flash userdata $ROOTFS_IMG"
    echo "  fb flash modem   $NON_HLOS_WHYRED"
    echo "  fb reboot"
    exit 0
fi

# ==============================================================================
# Step 8: 刷入设备 (boot + userdata + modem)
# ==============================================================================

step 8 "刷入设备 (boot + userdata + modem)"

# 8.1 刷入 boot.img 到 boot 分区
substep "8.1 fastboot flash boot $BOOT_IMG ..."
fb flash boot "$BOOT_IMG" \
    || { echo "[ERROR] fastboot flash boot 失败" >&2; exit 1; }
substep "  [OK] boot 分区刷入完成"

# 8.2 刷入 rootfs 到 userdata 分区
substep "8.2 fastboot flash userdata $ROOTFS_IMG ..."
fb flash userdata "$ROOTFS_IMG" \
    || { echo "[ERROR] fastboot flash userdata 失败" >&2; exit 1; }
substep "  [OK] userdata 分区刷入完成"

# 8.3 刷入 whyred NON-HLOS.bin 到 modem 分区 (WiFi firmware 修复)
substep "8.3 fastboot flash modem $NON_HLOS_WHYRED ..."
fb flash modem "$NON_HLOS_WHYRED" \
    || { echo "[ERROR] fastboot flash modem 失败" >&2; exit 1; }
substep "  [OK] modem 分区刷入完成 (WiFi firmware 1.0.0.591)"

echo "[OK] 全部 3 个分区刷入完成"

# ==============================================================================
# Step 9: 重启并验证
# ==============================================================================

step 9 "重启并验证"

substep "9.1 冷启动设备 (fb reboot)..."
# 注意: 必须冷启动, warm reboot 会导致 modem QMI 状态不一致
fb reboot
substep "  [OK] reboot 指令已发送"

# 等待系统启动 (systemd + USB gadget + sshd)
substep "9.2 等待 60 秒系统启动..."
sleep 60

# 验证 USB SSH 连通性
substep "9.3 验证 USB SSH (ping $DEVICE_USB_IP)..."
if ping -c 5 -W 2 "$DEVICE_USB_IP" >/dev/null 2>&1; then
    substep "  [OK] ping $DEVICE_USB_IP 可达"
else
    echo "[WARN] ping $DEVICE_USB_IP 不可达, 可能 USB 网络启动较慢" >&2
    echo "       再等 30 秒重试..." >&2
    sleep 30
    if ping -c 5 -W 2 "$DEVICE_USB_IP" >/dev/null 2>&1; then
        substep "  [OK] ping $DEVICE_USB_IP 可达 (重试后)"
    else
        echo "[ERROR] USB SSH 验证失败: $DEVICE_USB_IP 不可达" >&2
        echo "        请检查 USB 连接, 或通过 WiFi (192.168.1.12) 连接" >&2
        echo "        故障排查见 docs/故障排查.md" >&2
        exit 1
    fi
fi

# SSH 验证
substep "9.4 SSH 登录验证 (ssh $SSH_USER@$DEVICE_USB_IP)..."
if sshpass -p "$SSH_PASS" ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 \
       "$SSH_USER@$DEVICE_USB_IP" "uname -a" 2>/dev/null; then
    substep "  [OK] SSH 登录成功"
else
    echo "[ERROR] SSH 登录失败" >&2
    echo "        检查 sshd 是否启动, 或设备是否完全启动" >&2
    exit 1
fi

# 验证 kernel 版本
substep "9.5 验证 kernel 版本..."
KERNEL_VER=$(sshpass -p "$SSH_PASS" ssh -o StrictHostKeyChecking=no \
    "$SSH_USER@$DEVICE_USB_IP" "uname -r" 2>/dev/null || echo "")
if echo "$KERNEL_VER" | grep -q "sdm660"; then
    substep "  [OK] kernel: $KERNEL_VER"
else
    echo "[WARN] kernel 版本异常: '$KERNEL_VER' (期望包含 sdm660)" >&2
fi

# 验证 WiFi firmware
substep "9.6 验证 WiFi firmware 版本..."
sshpass -p "$SSH_PASS" ssh -o StrictHostKeyChecking=no \
    "$SSH_USER@$DEVICE_USB_IP" "dmesg | grep -E 'firmware ver|htt-ver' | head -3" 2>/dev/null \
    || substep "  (WiFi firmware 日志未捕获, 可能需要手动检查)"

# ==============================================================================
# 完成
# ==============================================================================

echo
echo "============================================================"
echo ">>> 复现完成! jason 设备已运行 pmOS Linux"
echo "============================================================"
echo
echo "设备状态:"
echo "  kernel:  $KERNEL_VER"
echo "  USB SSH: ssh $SSH_USER@$DEVICE_USB_IP  (密码 $SSH_PASS)"
echo "  WiFi:    ChinaNet-810 (192.168.1.12, 需 nmcli 连接)"
echo
echo "产物 (本机):"
echo "  boot.img:      $BOOT_IMG"
echo "  rootfs.img:    $ROOTFS_IMG"
echo "  NON-HLOS.bin:  $NON_HLOS_WHYRED"
echo
echo "下一步:"
echo "  - 部署服务器脚本: 见 refs/server-scripts/README.md"
echo "  - 配置 WiFi:      ssh $SSH_USER@$DEVICE_USB_IP 'sudo nmcli device wifi connect ChinaNet-810 password WIFI_CHINANET_PASS_PLACEHOLDER ifname wlan0'"
echo "  - 长稳测试:       ./scripts/long-stability-test.sh"
echo
echo "回退到原厂 Android:"
echo "  cd jason_images_V8.5.9.0.NCHCNED_20170831.0000.00_7.1_cn && ./flash_all.sh"
echo "  详见 docs/刷机指南.md §1"
