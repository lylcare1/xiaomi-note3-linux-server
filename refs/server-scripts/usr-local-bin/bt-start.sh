#!/bin/sh
# bt-start.sh - Idempotent Bluetooth bring-up for Xiaomi Note 3 (jason, WCN3990)
# Started from init_2nd.sh after wlan0 appears (BT shares UART bus with WiFi).
#
# Runs in rootfs context (chroot /sysroot). bluez 5.86 + dbus 1.16 + QCA UART driver.
# Firmware: qca/crbtfw21.tlv + qca/crnv21.bin (already in /lib/firmware/qca/)
#
# Idempotent: safe to call multiple times. Exits 0 if already running.
# Usage: bt-start.sh
#   sudo bt-start.sh           # foreground
#   nohup bt-start.sh &        # background

set -u

LOG_TAG="bt-start"
DBUS_PIDFILE="/run/dbus/dbus.pid"
DBUS_SOCKET="/run/dbus/system_bus_socket"
BLUETOOTHD="/usr/lib/bluetooth/bluetoothd"
BT_LOG="/var/log/bluetoothd.log"

log() { logger -t "$LOG_TAG" "$*" 2>/dev/null || echo "$LOG_TAG: $*"; }

# 1. Wait for hci0
for i in $(seq 1 30); do
    [ -d /sys/class/bluetooth/hci0 ] && break
    sleep 1
done
if [ ! -d /sys/class/bluetooth/hci0 ]; then
    log "ERROR: hci0 not found after 30s, exiting"
    exit 1
fi
log "hci0 detected"

# 2. Start dbus-daemon (bluetoothd requires D-Bus system bus)
if ! pgrep -x dbus-daemon >/dev/null 2>&1; then
    rm -f "$DBUS_PIDFILE" "$DBUS_SOCKET" 2>/dev/null
    mkdir -p /run/dbus
    dbus-uuidgen --ensure 2>/dev/null
    if dbus-daemon --system --fork 2>/dev/null; then
        sleep 1
        log "dbus-daemon started"
    else
        log "ERROR: dbus-daemon failed to start"
        exit 2
    fi
else
    log "dbus-daemon already running"
fi

# 3. Start bluetoothd
if ! pgrep -x bluetoothd >/dev/null 2>&1; then
    "$BLUETOOTHD" >"$BT_LOG" 2>&1 &
    sleep 3
    if pgrep -x bluetoothd >/dev/null 2>&1; then
        log "bluetoothd started (PID $(pgrep -x bluetoothd))"
    else
        log "ERROR: bluetoothd failed to start"
        exit 3
    fi
else
    log "bluetoothd already running"
fi

# 4. Power on hci0 + enable LE/BR-EDR
# Use bluetoothctl (D-Bus path) for clean state, fall back to hciconfig
bluetoothctl power on >/dev/null 2>&1
sleep 1
hciconfig hci0 up 2>/dev/null

# Enable LE and BR/EDR via mgmt socket
btmgmt -i hci0 le on >/dev/null 2>&1 || true
btmgmt -i hci0 bredr on >/dev/null 2>&1 || true
btmgmt -i hci0 connectable on >/dev/null 2>&1 || true
btmgmt -i hci0 name jason-linux >/dev/null 2>&1 || true

sleep 1

# 5. Verify
STATE=$(hciconfig hci0 2>/dev/null | grep -o 'UP\|DOWN' | head -1)
if [ "$STATE" = "UP" ]; then
    BD_ADDR=$(hciconfig hci0 2>/dev/null | grep -o 'BD Address: [0-9A-Fa-f:]*' | awk '{print $3}')
    log "OK: hci0 UP, addr=$BD_ADDR, name=jason-linux"
    exit 0
else
    log "ERROR: hci0 not UP after bring-up"
    exit 4
fi
