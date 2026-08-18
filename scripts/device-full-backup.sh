#!/bin/sh
# 设备端全系统备份元数据收集 + 块级备份
out=/tmp/backup-meta
mkdir -p $out
{
echo "=== date ==="; date
echo "=== boot tar md5 ==="; md5sum /tmp/boot-backup.tar.gz
echo "=== losetup ==="; losetup -l
echo "=== by-name ==="; ls -l /dev/block/by-name/ 2>/dev/null
echo "=== loop part sizes ==="; blockdev --getsize64 /dev/loop0p1 /dev/loop0p2
echo "=== blkid ==="; blkid
echo "=== cmdline ==="; cat /proc/cmdline
echo "=== fstab ==="; cat /etc/fstab
echo "=== kernel ==="; uname -a
echo "=== apk world ==="; cat /etc/apk/world
echo "=== network ==="; nmcli -t -f NAME,UUID,TYPE con show 2>/dev/null
} > $out/meta.txt 2>&1

# boot 分区 (mmcblk1pXX by-name/boot) 块级备份
BOOT_DEV=$(readlink -f /dev/block/by-name/boot)
echo "boot dev: $BOOT_DEV" >> $out/meta.txt
dd if=$BOOT_DEV bs=4M 2>>$out/meta.txt | gzip > $out/boot-block.img.gz

# loop 镜像头 (userdata 上的 pmOS_boot/pmOS_root 循环镜像所在位置)
LOOP_FILE=$(losetup -l | awk 'NR==2{print $6}')
echo "loop file: $LOOP_FILE" >> $out/meta.txt

# rootfs tar 全量 (运行态, 排除伪文件系统)
tar -C / --one-file-system \
    --exclude='./proc/*' --exclude='./sys/*' --exclude='./dev/*' \
    --exclude='./run/*' --exclude='./tmp/*' --exclude='./var/cache/*' \
    -czf $out/rootfs.tar.gz . 2>$out/rootfs-tar-errors.log

md5sum $out/* > $out/md5sums.txt 2>/dev/null
ls -la $out >> $out/meta.txt
