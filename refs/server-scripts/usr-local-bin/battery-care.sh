#!/bin/sh
# battery-care.sh - Battery health monitor for long-term server use
#
# Designed for Xiaomi Note 3 (jason, PM660 PMIC + pmi8998_fg).
# Since mainline kernel does NOT expose charge_control_limit sysfs,
# this script only MONITORS and ALERTS. Physical USB cycling is required
# to prevent battery swelling (long-term 100% charge).
#
# Alerts:
#   - health != Good: critical (battery degradation)
#   - temp > 45C: warning, > 55C: critical
#   - capacity > 95% for > 24h while charging: "unplug USB to cycle"
#   - capacity < 20%: warning
#   - voltage > 4.35V while full: stress warning
#
# Logging:
#   - /var/log/battery-care.log (append, with timestamp)
#   - syslog via logger (for motd / journalctl)
#
# systemd timer: runs every hour (battery-care.timer)

set -u

LOG_TAG="battery-care"
LOG_FILE="/var/log/battery-care.log"
STATE_FILE="/run/battery-care.state"  # persists across runs (tmpfs, lost on reboot)
BAT="/sys/class/power_supply/qcom-battery"
CHG="/sys/class/power_supply/pm660-charger"

# Read battery fields from uevent (works around missing individual sysfs files)
read_field() {
    field="$1"
    [ -r "$BAT/uevent" ] && grep "^POWER_SUPPLY_$field=" "$BAT/uevent" | cut -d= -f2
}
read_chg_field() {
    field="$1"
    [ -r "$CHG/uevent" ] && grep "^POWER_SUPPLY_$field=" "$CHG/uevent" | cut -d= -f2
}

# Current values
capacity=$(read_field CAPACITY)
voltage_uv=$(read_field VOLTAGE_NOW)
temp_tenth=$(read_field TEMP)
health=$(read_chg_field HEALTH)   # health only in charger uevent, not battery
status=$(read_field STATUS)
chg_status=$(read_chg_field STATUS)
chg_online=$(read_chg_field ONLINE)

# Normalize
capacity=${capacity:-0}
voltage_v=$(awk -v uv="$voltage_uv" 'BEGIN { if (uv+0>0) printf "%.3f", uv/1000000; else print "0" }')
temp_c=$(awk -v t="$temp_tenth" 'BEGIN { if (t+0>0) printf "%.1f", t/10; else print "0" }')
health=${health:-Unknown}
status=${status:-Unknown}
chg_status=${chg_status:-Unknown}
chg_online=${chg_online:-0}

now=$(date '+%Y-%m-%d %H:%M:%S')
ts=$(date +%s)

# Append to log file
mkdir -p "$(dirname "$LOG_FILE")"
echo "$now cap=${capacity}% v=${voltage_v}V t=${temp_c}C health=$health status=$status chg=$chg_status online=$chg_online" >> "$LOG_FILE"

# Trim log to last 1000 lines (keep ~41 days of hourly samples)
if [ -f "$LOG_FILE" ]; then
    lines=$(wc -l < "$LOG_FILE")
    if [ "$lines" -gt 1000 ]; then
        tail -800 "$LOG_FILE" > "$LOG_FILE.tmp" && mv "$LOG_FILE.tmp" "$LOG_FILE"
    fi
fi

# Track high-charge duration (for "unplug USB" warning)
mkdir -p "$(dirname "$STATE_FILE")"
high_since=$(cat "$STATE_FILE.high_since" 2>/dev/null || echo 0)
if [ "$capacity" -ge 95 ] && { [ "$chg_status" = "Full" ] || [ "$chg_status" = "Charging" ] || [ "$status" = "Full" ]; }; then
    if [ "$high_since" -eq 0 ]; then
        echo "$ts" > "$STATE_FILE.high_since"
        high_since=$ts
    fi
else
    echo 0 > "$STATE_FILE.high_since"
    high_since=0
fi

# === Alerts ===
alert=""
level="info"

# 1. Health degradation (critical)
if [ "$health" != "Good" ]; then
    alert="CRITICAL: battery health=$health (not Good). Replace battery soon."
    level="err"
fi

# 2. Temperature (warning > 45C, critical > 55C)
temp_int=$(awk -v t="$temp_c" 'BEGIN { print int(t) }')
if [ "$temp_int" -ge 55 ]; then
    alert="CRITICAL: battery temp=${temp_c}C (>=55). Shut down or cool immediately."
    level="err"
elif [ "$temp_int" -ge 45 ]; then
    alert="WARN: battery temp=${temp_c}C (>=45). Check ventilation."
    level="warning"
fi

# 3. Long-term high charge (warning > 24h at >=95%)
if [ "$high_since" -gt 0 ]; then
    hours=$(( (ts - high_since) / 3600 ))
    if [ "$hours" -ge 24 ]; then
        alert="WARN: battery at >=95% for ${hours}h. Unplug USB to cycle (discharge to 30-50%, then recharge to 80%). Prevents swelling."
        level="warning"
    fi
fi

# 4. Low capacity (warning < 20%)
if [ "$capacity" -lt 20 ] 2>/dev/null; then
    alert="WARN: battery capacity=${capacity}%. Charge soon."
    level="warning"
fi

# 5. High voltage while full (stress)
if [ "$status" = "Full" ] && awk -v v="$voltage_v" 'BEGIN { exit !(v > 4.35) }'; then
    alert="WARN: battery full but voltage=${voltage_v}V (>4.35). Stress on cells. Unplug USB."
    level="warning"
fi

# Emit alert
if [ -n "$alert" ]; then
    logger -t "$LOG_TAG" -p "user.$level" "$alert"
    echo "$now $alert" >> "$LOG_FILE"
    # Write to motd-readable warning file
    echo "$now $alert" > /run/battery-care.alert
else
    rm -f /run/battery-care.alert 2>/dev/null
fi

exit 0
