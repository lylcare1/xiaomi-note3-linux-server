#!/bin/sh
# 对应设备 /usr/local/bin/config-backup.sh
# 来源: docs/troubleshooting.md §7.10.1 (P2-1 配置自动备份)
# 频率: weekly Monday (config-backup.timer)
# 功能: tar.gz 备份关键配置到 /var/backups, 保留 28 天
# 日志: logger -t config-backup
#
# 备份清单 (~25 项):
#   - sysctl / journald / sshd / timesyncd 配置
#   - 所有 systemd unit (/etc/systemd/system/)
#   - 所有 /usr/local/bin 脚本
#   - /etc/{fstab,hostname,hosts,passwd,group,shadow,sudoers,nftables.conf}
#   - apk repositories

TAG="config-backup"
BACKUP_DIR="/var/backups"
DATE=$(date +%Y%m%d)
BACKUP_FILE="$BACKUP_DIR/config-backup-$DATE.tar.gz"
RETENTION_DAYS=28

mkdir -p "$BACKUP_DIR"

# 备份清单 (相对根路径)
BACKUP_PATHS="
/etc/sysctl.d/
/etc/systemd/journald.conf.d/
/etc/ssh/sshd_config.d/
/etc/systemd/timesyncd.conf
/etc/systemd/system/
/usr/local/bin/
/etc/fstab
/etc/hostname
/etc/hosts
/etc/passwd
/etc/group
/etc/shadow
/etc/sudoers
/etc/nftables.conf
/etc/apk/repositories
"

# 构造 tar 参数 (只包含存在的文件/目录)
tar_args=""
for p in $BACKUP_PATHS; do
    if [ -e "$p" ]; then
        tar_args="$tar_args $p"
    fi
done

if [ -z "$tar_args" ]; then
    logger -t "$TAG" "WARN no backup paths found"
    exit 1
fi

# 创建备份 (tar 默认不 follow 符号链接)
if ! tar czf "$BACKUP_FILE" $tar_args 2>/dev/null; then
    logger -t "$TAG" "WARN tar backup failed"
    exit 1
fi

size=$(wc -c < "$BACKUP_FILE" 2>/dev/null)
logger -t "$TAG" "backup created: $BACKUP_FILE (${size} bytes)"

# 清理 28 天前的备份
old_count=$(find "$BACKUP_DIR" -name "config-backup-*.tar.gz" -mtime +"$RETENTION_DAYS" 2>/dev/null | wc -l)
if [ "$old_count" -gt 0 ]; then
    find "$BACKUP_DIR" -name "config-backup-*.tar.gz" -mtime +"$RETENTION_DAYS" -delete 2>/dev/null
    logger -t "$TAG" "deleted $old_count old backup(s) older than $RETENTION_DAYS days"
fi
