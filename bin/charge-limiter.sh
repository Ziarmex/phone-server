#!/bin/bash
CHG_CTRL=/sys/class/power_supply/battery/input_suspend
CAPACITY=$(cat /sys/class/power_supply/battery/capacity 2>/dev/null)
STATUS=$(cat /sys/class/power_supply/battery/status 2>/dev/null)
[ -z "$CAPACITY" ] || [ -z "$STATUS" ] && exit 1
if [ "$CAPACITY" -ge 50 ] && [ "$STATUS" != "Discharging" ]; then
    echo 1 > "$CHG_CTRL"
elif [ "$CAPACITY" -le 45 ]; then
    echo 0 > "$CHG_CTRL"
fi
