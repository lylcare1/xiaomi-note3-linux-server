#!/bin/bash
# USB NCM gadget (172.16.42.1) via ConfigFS.
# Idempotent: configfs 不允许覆盖已存在的 symlink/属性，全部先判断再写。
set -e
G=/sys/kernel/config/usb_gadget/g1
mkdir -p "$G"
cd "$G"
[ -s idVendor ] || echo 0x18d1 > idVendor
[ -s idProduct ] || echo 0xd001 > idProduct
mkdir -p strings/0x409
echo "xiaomi-jason-linux" > strings/0x409/product
mkdir -p functions/ncm.usb0
mkdir -p configs/c.1/strings/0x409
echo "NCM" > configs/c.1/strings/0x409/configuration
# configfs 不允许覆盖 symlink; 已存在则跳过
if [ ! -e configs/c.1/ncm.usb0 ]; then
    ln -s functions/ncm.usb0 configs/c.1/ncm.usb0
fi
# UDC 已绑定同值时写会报 EBUSY, 先判断
CUR_UDC=$(cat UDC 2>/dev/null || true)
UDC=$(ls /sys/class/udc | head -1)
if [ "$CUR_UDC" != "$UDC" ]; then
    echo "$UDC" > UDC
fi
ip addr add 172.16.42.1/16 dev usb0 2>/dev/null || true
ip link set usb0 up 2>/dev/null || true
