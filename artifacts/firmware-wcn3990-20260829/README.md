# WCN3990 WiFi 固件三件套 (2026-08-29 修复用)

来源: linux-firmware 上游 https://git.kernel.org/pub/scm/linux/kernel/git/firmware/linux-firmware.git/plain/ath10k/WCN3990/hw1.0/

| 文件 | md5 | 说明 |
|---|---|---|
| wlanmdsp.mbn | 259b4f9e4aef57a5051f27a201653262 | 主固件 WLAN.HL.2.0-01387 (替换 modem 分区 2019 版 WLAN.HL.1.0.1.c2-00538) |
| board-2.bin | 420356ebbf84fe34149ba470932fccaa | board 数据 (原缺失) |
| firmware-5.bin | d16e3444f68ee48c548a891b9f9279e1 | feature flags (上游版) |

安装路径 (设备): /lib/firmware/ath10k/WCN3990/hw1.0/
原固件备份 (设备): /var/backups/ath10k-wcn3990-orig/
修复背景: HANDOVER.md §7.8 (2026-08-29 固件崩溃归零)
