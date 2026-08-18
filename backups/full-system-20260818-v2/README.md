# 全系统备份 2026-08-18 v2 (r36 后基线)

**这是当前权威备份**。v1 (`full-system-20260818/`) 是 14:05 产物, boot 为 r35, rootfs 模块亦旧, 仅作历史回退层次保留。

## 与 v1 的差异

| 项 | v1 (14:05) | v2 (18:59, 本包) |
|---|---|---|
| boot 分区 | r35 (无 charge_behaviour) | **r36** (initramfs 固化, 重启零依赖) |
| rootfs qcom_smbx | r35 模块 | **r36 模块** (md5 5cfe139c) |
| charge-guard | r2 | **r3** (charge_behaviour 硬件停充) |
| 内核编译号 | #36 | #37 (2026-08-18 08:31) |

## 内容清单

| 文件 | 大小 | md5 | 说明 |
|---|---|---|---|
| `rootfs.tar.gz` | 268MB | b9c60f91 | rootfs 全量 (busybox tar, 排除 proc/sys/dev/run/tmp/media/mnt/var/cache), 零错误 |
| `boot/boot-partition-dd.img.gz` | 23.7MB | abff0eb6 | boot 分区块级镜像 (mmcblk1p62, 64MB; **前 22.7MB md5=4b2c5e53 已验证 == artifacts/boot-r36-20260818.img**) |
| `partition-metadata.txt` | 9KB | c7ed740a | 分区表/blkid/cmdline/fstab/模块 srcversion/charge-guard 状态 |

## 校验

```bash
cd backups/full-system-20260818-v2 && md5sum -c md5sums.txt
```

## 恢复方法

### 场景 A: 系统能启动 → 恢复 rootfs 文件

```bash
mkdir -p /tmp/restore && tar -xzf rootfs.tar.gz -C /tmp/restore
sshpass -p 'DEVICE_PASS_PLACEHOLDER' rsync -avz --exclude=proc --exclude=sys --exclude=dev \
  --exclude=run --exclude=tmp --exclude=media --exclude=mnt /tmp/restore/ user@172.16.42.1:/
```

### 场景 B: boot 分区损坏 → 恢复 boot (fastboot)

```bash
gunzip -c boot/boot-partition-dd.img.gz > /tmp/boot-r36-restore.img
# 设备进 fastboot (长按电源+音量-, 或 SSH: sudo reboot bootloader)
sudo fastboot flash boot /tmp/boot-r36-restore.img
```
镜像 64MB = 完整分区, fastboot flash 直接可用 (bootloader 只读前 22.7MB 有效部分)。

### 场景 C: 系统不能启动 → 全流程

1. 场景 B 先恢复 boot
2. 若 rootfs 也坏: `pmbootstrap install` 新 rootfs → `fastboot flash userdata` → 场景 A rsync 恢复配置
   (注意: 重刷后 UUID 变化, 用 `./scripts/deploy.sh --update-uuid` 同步 boot.img cmdline)

### 场景 D: 完全变砖 → 回原厂

`cd jason_images_* && ./flash_all.sh` (见 docs/刷机指南.md)

## 关键事实 (恢复后核对)

- kernel: 6.19.10-sdm660 #37, qcom_smbx srcversion **66A494BF62A12015D20C5B6** (r36)
- root UUID: 5a0e068c-3942-46a2-acf8-285d19520550 / boot(loop0p1): 7d83c53d-b15b-467b-a4ca-70884082589a
- boot 分区: mmcblk1p62, PARTUUID 07037285-39d3-94fb-3681-36e74659219d
- cmdline 关键参数: `cpuidle.off=1` (勿删)
- 恢复后自检: `cat /sys/class/power_supply/pm660-charger/charge_behaviour` 应输出 `[auto] inhibit-charge`

## 备份方式 (可复现)

```bash
# 设备端 (root): /tmp/device-full-backup-v2.sh — v1 脚本有三处 bug 勿再用:
#   1. /dev/block/by-name/ 不存在 → 必须 /dev/disk/by-partlabel/boot
#   2. busybox tar 无 --one-file-system → 用显式 --exclude=
#   3. dd/blockdev 需 sudo
# 拉回本地: ssh 'cat <file>' > local (设备无 scp)
```
