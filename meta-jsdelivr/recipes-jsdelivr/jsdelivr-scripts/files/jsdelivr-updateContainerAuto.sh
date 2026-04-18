#!/bin/bash

# Source shared utilities (includes LED functions)
source /usr/bin/jsdelivr-utils.sh

echo "JSDELIV AUTO Update start" > /dev/tty5

# Set LED to fast green blinking to indicate update in progress
led_container_starting

echo "STOPING the MANDATORY reboot script" > /dev/tty5
killall -STOP jsdelivr-mandatoryReboot.sh
killall -STOP jsdelivr-systemMonitor.sh


killall  -9 jsdelivr-systemWatchdog.sh
sleep 1
/usr/bin/jsdelivr-keepWatchdogHappy.sh &

docker stop $(docker ps -a -q)

echo "Initiate image download" > /dev/tty5

if ! docker pull globalping/globalping-probe:latest; then
    echo "Image download FAILED" > /dev/tty5
    killall -CONT jsdelivr-mandatoryReboot.sh
    killall -CONT jsdelivr-systemMonitor.sh
    killall jsdelivr-keepWatchdogHappy.sh
    exit 1
fi

echo "Image download FINISHED" > /dev/tty5

sync

echo "Main image repo update finished" > /dev/tty5

echo "JSDELIV AUTO Update FINISHED" > /dev/tty5
echo "Resuming the MANDATORY reboot script" > /dev/tty5
killall -CONT jsdelivr-mandatoryReboot.sh
killall -CONT jsdelivr-systemMonitor.sh
killall jsdelivr-keepWatchdogHappy.sh

# Restore LED to stable state (systemMonitor will take over after resume)
led_container_stable
