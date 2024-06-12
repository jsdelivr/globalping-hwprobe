#!/bin/bash

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


killall jsdelivr_systemWatchdog
docker kill $(docker ps -q)
reboot &


echo "Waiting for watchdog reboot or normal system reboot" > /dev/tty4
while :; do  sleep 2; done


