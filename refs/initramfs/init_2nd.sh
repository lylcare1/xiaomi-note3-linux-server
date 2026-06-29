#!/bin/busybox ash
# shellcheck disable=SC1091

# This is the "real" init.sh script, it's either jumped to immediately
# from init.sh, or loaded from initramfs-extra on the boot partition
# on space constrained devices with deviceinfo_create_initfs_extra="true".

# The set -a in init.sh only exports variables, not functions
. /init_functions.sh
. /init_functions_2nd.sh

# Handle halt/poweroff/reboot
# Signals from busybox/halt.c
trap 'halt -f' USR1
trap 'poweroff -f' USR2
trap 'reboot -f' TERM

# Run udev early, before splash, to make sure any relevant display drivers are
# loaded in time
setup_udev

setup_usb_network
start_unudhcpd

# === DEBUG: Start shell listener on USB for early access ===
# USB NCM works for ~15-30s after boot; start a shell listener immediately
(
    while true; do
        /bin/busybox-extras nc -l -p 2222 -e /bin/sh 2>/dev/null || \
        /bin/busybox nc -l -p 2222 -e /bin/sh 2>/dev/null || \
        sleep 1
    done
) &
echo "$LOG_PREFIX DEBUG: nc shell on port 2222 (PID $!)" > /dev/kmsg

# Also send dmesg to host for logging (host must listen on port 3333)
(
    sleep 3
    while true; do
        dmesg 2>/dev/null | /bin/busybox-extras nc 172.16.42.2 3333 2>/dev/null
        sleep 5
    done
) &
echo "$LOG_PREFIX DEBUG: dmesg sender to 172.16.42.2:3333 (PID $!)" > /dev/kmsg
# === END DEBUG ===

# DEBUG halt removed - boot proceeds directly

# Start splash
if [ "$nosplash" != "y" ] && [ "$IN_CI" = "false" ]; then
	setup_framebuffer
	splash_start
	splash_set_message "Loading"
fi

setup_dynamic_partitions "${deviceinfo_super_partitions:=}"

run_hooks /hooks

if [ "$debug_shell" = "y" ]; then
	debug_shell
fi

check_keys

# If running from initramfs-extra this will be a no-op since it was
# called before to mount the boot partition
mount_subpartitions

run_hooks /hooks-extra

wait_root_partition
delete_old_install_partition
resize_root_partition
unlock_root_partition
resize_root_filesystem
mount_root_partition
resize_filesystem_after_mount /sysroot

# Mount boot partition into sysroot if needed since some
# old installations don't have a proper /etc/fstab file. See #2800
if [ -z "$(cat /sysroot/etc/fstab | grep -v "#" | tr -d '[:space:]')" ]; then
	wait_boot_partition
	mount_boot_partition /sysroot/boot "rw"
fi

init="/sbin/init"
setup_bootchart2

# Switch root
run_hooks /hooks-cleanup

echo "Switching root"

# Restore stdout and stderr to their original values if they
# were stashed
if [ -e "/proc/1/fd/3" ]; then
	exec 1>&3 2>&4
elif [ "$debug_shell" != "y" ]; then
	echo "$LOG_PREFIX Disabling console output again (use 'pmos.debug-shell' to keep it enabled)"
	exec >/dev/null 2>&1
fi

# Make it clear that we're at the end of the initramfs
splash_set_message "Starting"

# Re-enable kmsg ratelimiting (might have been disabled for logging)
echo ratelimit > /proc/sys/kernel/printk_devkmsg

# Vibrate to indicate that we are booting
if [ "$IN_CI" != "true" ]; then
	beebzzr &
fi

# === DEBUG: Start sshd from rootfs before switch_root ===
# USB NCM works in initramfs; start sshd now so it survives switch_root
if [ -x /sysroot/usr/sbin/sshd.pam ]; then
    mkdir -p /sysroot/run/sshd 2>/dev/null
    # Mount necessary filesystems for chroot
    mount -t proc proc /sysroot/proc 2>/dev/null
    mount -t sysfs sysfs /sysroot/sys 2>/dev/null
    mount -t devtmpfs devtmpfs /sysroot/dev 2>/dev/null
    mount -t tmpfs tmpfs /sysroot/run 2>/dev/null
    # Ensure host keys exist
    if [ ! -f /sysroot/etc/ssh/ssh_host_ed25519_key ]; then
        chroot /sysroot /usr/bin/ssh-keygen -A 2>/dev/null
    fi
    chroot /sysroot /usr/sbin/sshd.pam 2>/dev/null
    echo "$LOG_PREFIX DEBUG: sshd started from initramfs" > /dev/kmsg
    echo "$LOG_PREFIX DEBUG: usb0 IP: $(ip -4 addr show usb0 2>/dev/null | grep -o 'inet [0-9.]*')" > /dev/kmsg
fi
# === END DEBUG ===

# Don't kill unudhcpd - it provides DHCP for USB network
# Don't kill udevd - needed for firmware loading (remoteproc, etc.)
killall syslogd 2>/dev/null

# Don't kill sh processes - nc shell listener needs to survive pivot_root

# cleanup after ourselves
rm /dev/log 2>/dev/null || true

# === STAY IN INITRAMFS - DO NOT SWITCH ROOT ===
# USB NCM is stable in initramfs but breaks when systemd starts.
# Stay in initramfs and provide server functionality via chroot to rootfs.
# SSH on port 22, nc shell on port 2222.

# Ensure DNS works in chroot
echo "nameserver 8.8.8.8" > /sysroot/etc/resolv.conf 2>/dev/null

# Save dmesg for debugging
dmesg > /sysroot/var/log/initramfs-dmesg.log 2>/dev/null

echo "$LOG_PREFIX INFO: Server ready - staying in initramfs" > /dev/kmsg
echo "$LOG_PREFIX INFO: SSH on port 22, nc shell on port 2222" > /dev/kmsg

# === Load kernel modules and start remoteprocs ===
# This enables WiFi (WCN3990) and other Qualcomm subsystems.
# Runs in background so it doesn't block PID 1.
(
    sleep 5  # Wait for system to stabilize

    echo "$LOG_PREFIX INFO: Loading Qualcomm modules..." > /dev/kmsg

    # Create module symlink so modprobe finds modules in rootfs
    # (initramfs only has modules.dep metadata, actual .ko.zst files are in rootfs)
    rm -rf /lib/modules/6.19.10-sdm660
    ln -s /sysroot/lib/modules/6.19.10-sdm660 /lib/modules/6.19.10-sdm660

    # QRTR (Qualcomm IPC Router) - needed for QMI communication
    modprobe qrtr 2>/dev/null
    modprobe qrtr-smd 2>/dev/null

    # Remoteproc drivers - for ADSP/CDSP/Modem subsystems
    modprobe qcom_q6v5 2>/dev/null
    modprobe qcom_q6v5_pas 2>/dev/null
    modprobe qcom_q6v5_mss 2>/dev/null
    modprobe qcom_wcnss_pil 2>/dev/null
    modprobe qcom_pd_mapper 2>/dev/null
    modprobe pdr_interface 2>/dev/null
    modprobe mdt_loader 2>/dev/null
    modprobe rmtfs_mem 2>/dev/null

    # WiFi drivers
    modprobe ath 2>/dev/null
    modprobe ath10k_core 2>/dev/null
    modprobe ath10k_snoc 2>/dev/null
    modprobe wcnss_ctrl 2>/dev/null

    # Copy firmware from rootfs to initramfs (kernel firmware loader uses initramfs root)
    if [ -d /sysroot/lib/firmware/postmarketos ]; then
        mkdir -p /lib/firmware/postmarketos
        cp /sysroot/lib/firmware/postmarketos/* /lib/firmware/postmarketos/ 2>/dev/null
        echo "$LOG_PREFIX INFO: Firmware copied to initramfs" > /dev/kmsg
    fi

    # Also copy ath10k WiFi firmware
    if [ -d /sysroot/lib/firmware/ath10k ]; then
        mkdir -p /lib/firmware/ath10k
        cp -r /sysroot/lib/firmware/ath10k/* /lib/firmware/ath10k/ 2>/dev/null
    fi

    # Create modemst partition symlinks for rmtfs
    mkdir -p /dev/block/by-name 2>/dev/null
    ln -sf /dev/disk/by-partlabel/modemst1 /dev/block/by-name/modemst1 2>/dev/null
    ln -sf /dev/disk/by-partlabel/modemst2 /dev/block/by-name/modemst2 2>/dev/null
    ln -sf /dev/disk/by-partlabel/fsg /dev/block/by-name/fsg 2>/dev/null

    # Start ADSP (Audio DSP) - provides QMI services
    if [ -f /sys/class/remoteproc/remoteproc0/state ]; then
        echo start > /sys/class/remoteproc/remoteproc0/state 2>/dev/null
        sleep 5
        ADSP_STATE=$(cat /sys/class/remoteproc/remoteproc0/state 2>/dev/null)
        echo "$LOG_PREFIX INFO: ADSP state: $ADSP_STATE" > /dev/kmsg
    fi

    # Start modem support services BEFORE modem starts
    # Without diag-router, modem diag task starves and crashes every ~40s
    # Without rmtfs/tqftpserv, modem can't access modemst partitions
    # These services must run in rootfs context (chroot /sysroot before pivot_root)
    chroot /sysroot /usr/bin/rmtfs -r -P -s > /sysroot/tmp/rmtfs.log 2>&1 &
    chroot /sysroot /usr/bin/tqftpserv > /sysroot/tmp/tqftpserv.log 2>&1 &
    chroot /sysroot /usr/bin/diag-router > /sysroot/tmp/diag-router.log 2>&1 &
    sleep 3
    echo "$LOG_PREFIX INFO: Modem services started (rmtfs, tqftpserv, diag-router)" > /dev/kmsg

    # Start Modem (MPSS) - provides WLFW service (QRTR service 69/0x45) for WiFi
    # wlanmdsp.mbn runs on modem DSP, ath10k_snoc connects via QMI
    if [ -f /sys/class/remoteproc/remoteproc2/state ]; then
        echo start > /sys/class/remoteproc/remoteproc2/state 2>/dev/null
        echo "$LOG_PREFIX INFO: Modem starting (wait 30s for WLFW service)" > /dev/kmsg
        sleep 30
        MODEM_STATE=$(cat /sys/class/remoteproc/remoteproc2/state 2>/dev/null)
        echo "$LOG_PREFIX INFO: Modem state: $MODEM_STATE" > /dev/kmsg
    fi

    # ath10k_snoc auto-probes when WLFW service appears on QRTR
    # No need to manually unbind/bind - qmi_add_lookup waits for service
    if ip link show wlan0 >/dev/null 2>&1; then
        echo "$LOG_PREFIX INFO: wlan0 interface available!" > /dev/kmsg
    else
        echo "$LOG_PREFIX WARN: wlan0 not available yet (check modem stability)" > /dev/kmsg
    fi

    # Save module load status
    lsmod > /sysroot/var/log/initramfs-modules.log 2>/dev/null
    dmesg > /sysroot/var/log/initramfs-boot.log 2>/dev/null
) &

echo "$LOG_PREFIX INFO: Module loader started in background (PID $!)" > /dev/kmsg

# === Start WiFi in background (waits for wlan0 from module loader) ===
# wpa_supplicant + udhcpc connect to ChinaNet-810 automatically on boot
(
    # Wait for wlan0 to appear (module loader starts it ~40s after boot)
    for i in $(seq 1 60); do
        if ip link show wlan0 >/dev/null 2>&1; then break; fi
        sleep 1
    done
    if ! ip link show wlan0 >/dev/null 2>&1; then
        echo "$LOG_PREFIX WARN: wlan0 not found after 60s, WiFi start skipped" > /dev/kmsg
        exit 0
    fi
    sleep 3  # Wait for ath10k to fully initialize
    chroot /sysroot /usr/local/bin/wifi-start.sh >/sysroot/var/log/wifi-start.log 2>&1
    ip4=$(ip -4 addr show wlan0 2>/dev/null | grep -o 'inet [0-9.]*' | awk '{print $2}')
    echo "$LOG_PREFIX INFO: wifi-start completed, wlan0 ip=${ip4:-none}" > /dev/kmsg
) &
echo "$LOG_PREFIX INFO: WiFi starter started in background (PID $!)" > /dev/kmsg

# === Start interactive shell on tty1 (physical screen) ===
# Gives user a usable terminal on the phone display
(
    sleep 10  # Wait for kernel console output to settle
    while true; do
        # Clear screen and show banner
        printf '\033[2J\033[H' > /dev/tty1
        echo "========================================" > /dev/tty1
        echo " Xiaomi Mi Note 3 (jason) Linux Server" > /dev/tty1
        echo " Initramfs mode - tty1 shell" > /dev/tty1
        echo "========================================" > /dev/tty1
        echo "" > /dev/tty1
        # Start interactive shell with rootfs context (chroot for full toolset)
        setsid sh -c 'exec chroot /sysroot /bin/sh' < /dev/tty1 > /dev/tty1 2>&1
        sleep 1  # Brief pause before respawn on exit
    done
) &
echo "$LOG_PREFIX INFO: Interactive shell on tty1 (screen) started" > /dev/kmsg

# === Start server monitoring daemon (initramfs mode) ===
# Replaces 8 systemd timers with a single loop-based scheduler
# Runs in rootfs context (chroot /sysroot) for access to scripts/tools
(
    sleep 15  # Wait for sshd + rootfs to stabilize

    # Start syslogd in rootfs context (for logger command)
    chroot /sysroot /sbin/syslogd -O /var/log/messages -s 100 2>/dev/null
    echo "$LOG_PREFIX INFO: syslogd started (rootfs context)" > /dev/kmsg

    # Restore time from fake-RTC if available
    chroot /sysroot /usr/local/bin/fake-rtc-restore.sh 2>/dev/null

    # Start server-daemon (health-check, temp-monitor, net-monitor, etc.)
    chroot /sysroot /usr/local/bin/server-daemon.sh &
    echo "$LOG_PREFIX INFO: server-daemon started (PID $!)" > /dev/kmsg
) &

# Keep PID 1 alive forever
# USB NCM, sshd, nc shell all running as background processes
while true; do
    sleep 300
done
