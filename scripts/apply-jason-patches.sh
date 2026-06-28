#!/bin/sh
# apply-jason-patches.sh
# 用途: 把 refs/jason-pmaports-patches/ 里的所有 jason 移植改动
#       应用到一个干净的 pmaports 检出上 (pmbootstrap cache_git/pmaports)。
#
# 用法: apply-jason-patches.sh [PMAPORTS_DIR]
#   默认 PMAPORTS_DIR=~/.local/var/pmbootstrap/cache_git/pmaports
#
# 幂等: 可重复运行, 已存在的目标目录/文件会被覆盖。
#
# 改动清单:
#   - device-xiaomi-jason/         (新设备包, 整目录)
#   - firmware-xiaomi-jason/       (新 firmware 包, 整目录)
#   - linux-postmarketos-qcom-sdm660/0001-dts-qcom-add-sdm660-xiaomi-jason.patch
#   - linux-postmarketos-qcom-sdm660/0002-ath10k-wcn3990-skip-psmode.patch
#   - linux-postmarketos-qcom-sdm660/0003-cpufreq-hw-sdm660.patch
#   - linux-postmarketos-qcom-sdm660/APKBUILD                                  (覆盖)
#   - linux-postmarketos-qcom-sdm660/config-postmarketos-qcom-sdm660.aarch64   (覆盖)

set -eu

# 解析脚本所在目录 (项目根 = scripts/ 的父目录)
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
PROJECT_ROOT=$(cd "$SCRIPT_DIR/.." && pwd)
PATCH_SRC="$PROJECT_ROOT/refs/jason-pmaports-patches"

PMAPORTS_DIR="${1:-$HOME/.local/var/pmbootstrap/cache_git/pmaports}"
DEVICE_TESTING="$PMAPORTS_DIR/device/testing"
KERNEL_DIR="$DEVICE_TESTING/linux-postmarketos-qcom-sdm660"

echo "=== apply-jason-patches.sh ==="
echo "Patch 源:    $PATCH_SRC"
echo "目标 pmaports: $PMAPORTS_DIR"
echo

# --- 健全性检查 ---
if [ ! -d "$PATCH_SRC" ]; then
    echo "[ERROR] Patch 源目录不存在: $PATCH_SRC" >&2
    exit 1
fi
if [ ! -d "$PATCH_SRC/device-xiaomi-jason" ] || \
   [ ! -d "$PATCH_SRC/firmware-xiaomi-jason" ] || \
   [ ! -d "$PATCH_SRC/linux-postmarketos-qcom-sdm660" ]; then
    echo "[ERROR] Patch 源内容不完整, 期望包含 3 个子目录:" >&2
    echo "        device-xiaomi-jason/ firmware-xiaomi-jason/ linux-postmarketos-qcom-sdm660/" >&2
    exit 1
fi
if [ ! -d "$PMAPORTS_DIR/.git" ]; then
    echo "[ERROR] pmaports 仓库不存在于: $PMAPORTS_DIR" >&2
    echo "        请把 pmaports 路径作为参数传入, 或先运行 pmbootstrap init。" >&2
    exit 1
fi
if [ ! -d "$DEVICE_TESTING" ]; then
    echo "[ERROR] device/testing/ 目录不存在: $DEVICE_TESTING" >&2
    exit 1
fi

# 确保内核子目录存在 (上游 pmaports 已有, 这里防御性创建)
mkdir -p "$KERNEL_DIR"

# --- Step 1: device-xiaomi-jason/ (整目录) ---
echo "[1/3] 复制 device-xiaomi-jason/ ..."
rm -rf "$DEVICE_TESTING/device-xiaomi-jason"
cp -rp "$PATCH_SRC/device-xiaomi-jason" "$DEVICE_TESTING/"
echo "     -> $(ls "$DEVICE_TESTING/device-xiaomi-jason" | tr '\n' ' ')"

# --- Step 2: firmware-xiaomi-jason/ (整目录, 含 board-data.bin) ---
echo "[2/3] 复制 firmware-xiaomi-jason/ ..."
rm -rf "$DEVICE_TESTING/firmware-xiaomi-jason"
cp -rp "$PATCH_SRC/firmware-xiaomi-jason" "$DEVICE_TESTING/"
echo "     -> $(ls "$DEVICE_TESTING/firmware-xiaomi-jason" | tr '\n' ' ')"

# --- Step 3: kernel patches + APKBUILD + config (覆盖) ---
echo "[3/3] 复制 linux-postmarketos-qcom-sdm660/ patches + APKBUILD + config ..."
cp -f "$PATCH_SRC/linux-postmarketos-qcom-sdm660/0001-dts-qcom-add-sdm660-xiaomi-jason.patch" \
      "$KERNEL_DIR/"
cp -f "$PATCH_SRC/linux-postmarketos-qcom-sdm660/0002-ath10k-wcn3990-skip-psmode.patch" \
      "$KERNEL_DIR/"
cp -f "$PATCH_SRC/linux-postmarketos-qcom-sdm660/0003-cpufreq-hw-sdm660.patch" \
      "$KERNEL_DIR/"
cp -f "$PATCH_SRC/linux-postmarketos-qcom-sdm660/APKBUILD" \
      "$KERNEL_DIR/"
cp -f "$PATCH_SRC/linux-postmarketos-qcom-sdm660/config-postmarketos-qcom-sdm660.aarch64" \
      "$KERNEL_DIR/"
echo "     -> $(ls "$KERNEL_DIR" | tr '\n' ' ')"

echo
echo "=== 应用完成 ==="
echo
echo "已应用到 $PMAPORTS_DIR:"
echo "  device/testing/device-xiaomi-jason/                 (新建设备包)"
echo "  device/testing/firmware-xiaomi-jason/               (新立 firmware 包)"
echo "  device/testing/linux-postmarketos-qcom-sdm660/     (3 patches + APKBUILD + config)"
echo
echo "下一步: 重新构建受影响的包"
echo "  pmbootstrap checksum device-xiaomi-jason firmware-xiaomi-jason linux-postmarketos-qcom-sdm660"
echo "  pmbootstrap build device-xiaomi-jason"
echo "  pmbootstrap build firmware-xiaomi-jason"
echo "  pmbootstrap build linux-postmarketos-qcom-sdm660"
echo "  pmbootstrap install"
