#!/bin/bash

# Source shared utilities
source /usr/bin/jsdelivr-utils.sh

# Detect boot device (SD card = mmcblk0, eMMC = mmcblk2)
detect_boot_device

BOOT_READY_FLAG="/tmp/.jsdelivr_boot_ready"

# Wait for boot to complete before starting watchdog counter
# This prevents premature recovery during normal boot sequence
echo "Waiting for boot ready flag..." > /dev/tty2
BOOT_READY_TIMEOUT=300
BOOT_READY_WAITED=0
while [ ! -f "$BOOT_READY_FLAG" ]; do
    echo "1" > /dev/watchdog0 2>/dev/null || true
    sleep 1
    BOOT_READY_WAITED=$((BOOT_READY_WAITED+1))
    if [ "$BOOT_READY_WAITED" -ge "$BOOT_READY_TIMEOUT" ]; then
        echo "Boot never became ready after ${BOOT_READY_TIMEOUT}s; stopping watchdog keepalives" > /dev/tty2
        break
    fi
done
echo "Boot ready, starting watchdog monitoring" > /dev/tty2

COUNTER=0
(( TTL_MAX= 60 * 5  ))
LAST_CHANCE=0
LIMIT=0
exec 4> /dev/watchdog0


while [ 1 ];
do
    COUNTER=$((COUNTER+1))
    echo "System WatchDog counter:$COUNTER Max:$TTL_MAX LAST_CHANCE:$LAST_CHANCE" > /dev/tty2
    if [ "$COUNTER" -gt "$TTL_MAX" ]; then
        echo "Container status is faulty" > /dev/tty2
        if [ "$LAST_CHANCE" -gt "$LIMIT" ]; then
            echo "Container recover attempt failed, resorting to full system reboot"  > /dev/tty2

            # Reset Docker storage (p6=docker) to force clean container reload
            # A/B layout: p3=rootfs-a, p4=rootfs-b, p5=persist, p6=docker, p7=docker_persist
            docker stop $(docker ps -a -q) 2>/dev/null
            systemctl stop docker 2>/dev/null
            umount /var/lib/docker 2>/dev/null
            DOCKER_PART="/dev/disk/by-label/docker"
            [ -b "$DOCKER_PART" ] && mkfs.ext4 -F "$DOCKER_PART"
            while :; do  sleep 2; done
        fi
        echo "1" >&4
        echo "Trying to recover container"  > /dev/tty2
        docker kill  globalping-probe
        echo "1" >&4
        docker kill  globalping-probe
        echo "1" >&4
        docker ps -a > /dev/tty2
        echo "1" >&4
        docker rm globalping-probe > /dev/tty2
        echo "1" >&4
        COUNTER=0
        LAST_CHANCE=$((LAST_CHANCE+1))
    else

        if [ -f /tmp/SYSTEM_STABLE ]; then
            echo "Container status is ok"  > /dev/tty2
            rm /tmp/SYSTEM_STABLE
            COUNTER=0
            LAST_CHANCE=0
        fi

    fi

    echo "1" >&4

    sleep 1

done
