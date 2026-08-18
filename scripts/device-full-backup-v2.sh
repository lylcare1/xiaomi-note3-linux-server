#!/bin/sh
# 设备端全系统备份 v2 (修正: by-partlabel 路径 + busybox tar 兼容 + sudo dd)
# 用法: 设备上以 root 运行: sudo sh /tmp/device-full-backup-v2.sh
set -e
out=/tmp/backup-meta
rm -rf $out
mkdir -p $out

{
echo "=== date ==="; date
echo "=== uname ==="; uname -a
echo "=== losetup ==="; losetup -l
echo "=== by-partlabel boot ==="; readlink -f /dev/disk/by-partlabel/boot
echo "=== blkid ==="; blkid
echo "=== cmdline ==="; cat /proc/cmdline
echo "=== fstab ==="; cat /etc/fstab
echo "=== apk world ==="; cat /etc/apk/world
echo "=== qcom_smbx srcversion ==="; modinfo qcom_smbx | grep -E 'srcversion|filename'
echo "=== charge-guard ==="; systemctl is-active charge-guard.timer; cat /run/charge-guard-mode 2>/dev/null
} > $out/meta.txt 2>&1

# boot 分区块级备份 (mmcblk1p62 via by-partlabel)
BOOT_DEV=$(readlink -f /dev/disk/by-partlabel/boot)
echo "boot dev: $BOOT_DEV" >> $out/meta.txt
dd if=$BOOT_DEV bs=4M status=none | gzip > $out/boot-block.img.gz

# rootfs tar 全量 (busybox tar: 无 --one-file-system, 用显式 exclude)
tar -C / -czf $out/rootfs.tar.gz \
    --exclude=proc --exclude=sys --exclude=dev \
    --exclude=run --exclude=tmp --exclude=media --exclude=mnt \
    --exclude=var/cache \
    . 2>$out/rootfs-tar-errors.log || true

md5sum $out/boot-block.img.gz $out/rootfs.tar.gz $out/meta.txt > $out/md5sums.txt
ls -la $out >> $out/meta.txt
echo "BACKUP-V2-DONE"
