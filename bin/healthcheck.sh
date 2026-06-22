#!/bin/bash
# Server health check - called by systemd timer every 5 minutes

# Log file
LOG=/var/log/healthcheck.log

# Check internet connectivity
ping -c 1 -W 5 8.8.8.8 >/dev/null 2>&1
if [ $? -ne 0 ]; then
    echo "$(date) WARN: No internet. Reconnecting WiFi..." >> $LOG
    nmcli connection down ZTE_2.4G_xUcN9A
    sleep 3
    nmcli connection up ZTE_2.4G_xUcN9A
fi

# Check essential services
for svc in caddy cloudflared ssh; do
    systemctl is-active --quiet $svc
    if [ $? -ne 0 ]; then
        echo "$(date) WARN: $svc was down. Restarting..." >> $LOG
        systemctl restart $svc
    fi
done
