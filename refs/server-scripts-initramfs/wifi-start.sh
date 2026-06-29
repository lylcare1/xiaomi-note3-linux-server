#!/bin/sh
# wifi-start.sh — Start WiFi (wpa_supplicant + udhcpc) if not already running
# Called from init_2nd.sh after modules load (wlan0 available)
# Idempotent: does NOT kill working instances, only starts what's missing
#
# Config: /etc/wpa_supplicant/wpa_supplicant.conf (persistent on rootfs)

TAG="wifi-start"
CONF="/etc/wpa_supplicant/wpa_supplicant.conf"
LOG="/var/log/wifi-start.log"

log() { echo "$(date '+%H:%M:%S') $*" >> "$LOG"; logger -t "$TAG" "$@" 2>/dev/null; }

# Wait for wlan0 interface
for i in $(seq 1 10); do
    if ip link show wlan0 >/dev/null 2>&1; then break; fi
    sleep 1
done
if ! ip link show wlan0 >/dev/null 2>&1; then
    log "ERROR wlan0 not found after 10s"
    exit 1
fi

# If wlan0 already has IPv4, nothing to do (already connected)
ip4=$(ip -4 addr show wlan0 2>/dev/null | grep -o 'inet [0-9.]*' | awk '{print $2}')
if [ -n "$ip4" ]; then
    log "OK already connected, wlan0 ip=$ip4"
    exit 0
fi

# Bring interface down (required for MAC change)
ip link set wlan0 down 2>/dev/null

# Set fixed MAC address (ath10k assigns random MAC on load; fix it for stable DHCP IP)
# 02: = locally administered, 1a:73:6b:03:01 = jason/sdm660/note3
ip link set dev wlan0 address 02:1a:73:6b:03:01 2>/dev/null

# Bring interface up
ip link set wlan0 up 2>/dev/null
sleep 1

# Start wpa_supplicant if not running
if ! pgrep -f "wpa_supplicant.*-i wlan0" >/dev/null 2>&1; then
    if [ -f "$CONF" ]; then
        mkdir -p /run/wpa_supplicant
        wpa_supplicant -B -i wlan0 -c "$CONF" 2>>"$LOG"
        log "wpa_supplicant started"
    else
        log "ERROR $CONF not found"
        exit 1
    fi
else
    log "wpa_supplicant already running"
fi

# Wait for wpa_state=COMPLETED (up to 25s)
state=""
for i in $(seq 1 25); do
    state=$(wpa_cli -i wlan0 status 2>/dev/null | grep "^wpa_state=" | cut -d= -f2)
    if [ "$state" = "COMPLETED" ]; then
        log "wpa handshake completed (${i}s)"
        break
    fi
    sleep 1
done

if [ "$state" != "COMPLETED" ]; then
    log "WARN wpa_state=$state (not COMPLETED after 25s)"
fi

# Start udhcpc if not running and no IPv4 yet
ip4=$(ip -4 addr show wlan0 2>/dev/null | grep -o 'inet [0-9.]*' | awk '{print $2}')
if [ -z "$ip4" ] && ! pgrep -f "udhcpc.*wlan0" >/dev/null 2>&1; then
    # -b: background if no lease, -t 5: 5 retries, -T 2: 2s between retries
    udhcpc -i wlan0 -b -t 5 -T 2 2>>"$LOG"
    log "udhcpc started"
    sleep 2
elif [ -n "$ip4" ]; then
    log "OK IPv4 already assigned: $ip4"
else
    log "udhcpc already running"
fi

# Final status
ip4=$(ip -4 addr show wlan0 2>/dev/null | grep -o 'inet [0-9.]*' | awk '{print $2}')
if [ -n "$ip4" ]; then
    log "OK wlan0 ip=$ip4"
else
    log "WARN wlan0 has no IPv4 (DHCP may still be negotiating)"
fi
