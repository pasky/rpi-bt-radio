#!/bin/bash
# Network watchdog: recover wlan0 on sustained loss, reboot as last resort.
# Logs to journal (persistent) so failures are diagnosable after the fact.
#
# Install to /usr/local/sbin/net-watchdog.sh and run via net-watchdog.service.
GW="$(ip route | awk '/^default/{print $3; exit}')"
[ -z "$GW" ] && GW="192.168.39.1"
INTERVAL=30
FAILS=0
SOFT=3   # ~90s: bounce wifi
HARD=6   # ~180s: reboot

logger -t net-watchdog "started, monitoring gateway $GW every ${INTERVAL}s"
while true; do
    if ping -c1 -W3 "$GW" >/dev/null 2>&1; then
        if [ "$FAILS" -ne 0 ]; then
            logger -t net-watchdog "gateway $GW reachable again after $FAILS fail(s)"
        fi
        FAILS=0
    else
        FAILS=$((FAILS+1))
        logger -t net-watchdog "gateway $GW UNREACHABLE (consecutive fail #$FAILS)"
        if [ "$FAILS" -eq "$SOFT" ]; then
            logger -t net-watchdog "soft recovery: bouncing wlan0 + restarting wpa_supplicant"
            ip link set wlan0 down; sleep 2; ip link set wlan0 up
            systemctl restart wpa_supplicant 2>/dev/null
        fi
        if [ "$FAILS" -ge "$HARD" ]; then
            logger -t net-watchdog "hard recovery: still down after soft attempt, rebooting"
            sync
            systemctl reboot
        fi
    fi
    sleep "$INTERVAL"
done
