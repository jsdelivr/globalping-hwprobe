#!/bin/bash

DAYS=3
RANDOM_OFFSET_DAYS=2



((RANDOM_OFFSET_MAX= 24*60*60*$RANDOM_OFFSET_DAYS))

((MANDATORY_REBOOT_PERIOD_BASE= 24*60*60*$DAYS))

((RANDOM_OFFSET= $RANDOM % $RANDOM_OFFSET_MAX ))

((MANDATORY_REBOOT_PERIOD= $MANDATORY_REBOOT_PERIOD_BASE + $RANDOM_OFFSET ))


echo "Mandatory reboot random offset is $RANDOM_OFFSET seconds" > /dev/tty4
echo "Mandatory reboot period base is $MANDATORY_REBOOT_PERIOD_BASE seconds" > /dev/tty4
echo "Mandatory reboot period is $MANDATORY_REBOOT_PERIOD seconds" > /dev/tty4

echo "Sleeping...." > /dev/tty4

sleep $MANDATORY_REBOOT_PERIOD


echo "It's time.... to UPDATE" > /dev/tty4

/usr/bin/jsdelivr-updateContainerAuto.sh

echo "It's time....to REBOOT" > /dev/tty4

# Don't reboot mid-update. If a USB update flag is present at /run/usb-update
# or jsdelivr-updateContainer.sh is running, a reboot here would interrupt a
# docker pull and leave the flag on the stick to retry next boot — possible
# infinite loop if the network is flaky. Defer until the update window closes.
DEFER_TRIES=0
while ls /run/usb-update/JSDELIVR.UPD /run/usb-update/JSDELIVR-DEV.UPD /run/usb-update/JSDELIVR.RESET 2>/dev/null \
   || pgrep -f jsdelivr-updateContainer\\.sh >/dev/null 2>&1; do
    DEFER_TRIES=$((DEFER_TRIES + 1))
    if [ "$DEFER_TRIES" -ge 30 ]; then
        echo "USB update still in progress after 30 retries (15min), rebooting anyway" > /dev/tty4
        break
    fi
    echo "USB update in progress, deferring mandatory reboot 30s ($DEFER_TRIES/30)" > /dev/tty4
    sleep 30
done

killall jsdelivr-systemWatchdog.sh
CONTAINERS=$(docker ps -q 2>/dev/null)
[ -n "$CONTAINERS" ] && docker kill $CONTAINERS
reboot &


echo "Waiting for watchdog reboot or normal system reboot" > /dev/tty4
while :; do  sleep 2; done


