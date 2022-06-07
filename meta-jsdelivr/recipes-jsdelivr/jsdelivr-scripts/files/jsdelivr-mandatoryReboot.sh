#!/bin/bash

DAYS=3
((MANDATORY_REBOOT_PERIOD= 24*60*60*$DAYS))

echo "Mandatory reboot period is $MANDATORY_REBOOT_PERIOD seconds"
echo "Sleeping...."
sleep $MANDATORY_REBOOT_PERIOD

echo "It's time...."

killall jsdelivr_systemWatchdog
docker kill $(docker ps -q)
reboot &
echo "Waiting for watchdog reboot or normal system reboot"
while :; do  sleep 2; done



