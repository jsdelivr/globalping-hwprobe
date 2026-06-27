#!/bin/bash

# Source shared utilities
source /usr/bin/jsdelivr-utils.sh

# Detect boot device (SD card = mmcblk0, eMMC = mmcblk2)
detect_boot_device

BOOT_READY_FLAG="/tmp/.jsdelivr_boot_ready"

# Open watchdog once; reuse FD 4 throughout. Closing without 'V' keeps the
# hardware timer armed (DW watchdog supports magic-close), so process exit
# triggers a HW reboot.
exec 4> /dev/watchdog0

# Wait for boot to complete before starting watchdog counter
# This prevents premature recovery during normal boot sequence
echo "Waiting for boot ready flag..." > /dev/tty2
BOOT_READY_TIMEOUT=300
BOOT_READY_WAITED=0
while [ ! -f "$BOOT_READY_FLAG" ]; do
    echo "1" >&4 2>/dev/null || true
    sleep 1
    BOOT_READY_WAITED=$((BOOT_READY_WAITED+1))
    if [ "$BOOT_READY_WAITED" -ge "$BOOT_READY_TIMEOUT" ]; then
        echo "Boot never became ready after ${BOOT_READY_TIMEOUT}s; exiting so HW watchdog can reboot" > /dev/tty2
        exit 1
    fi
done
echo "Boot ready, starting watchdog monitoring" > /dev/tty2

COUNTER=0
(( TTL_MAX= 60 * 5  ))
LAST_CHANCE=0
LIMIT=0


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
            CONTAINERS=$(docker ps -aq 2>/dev/null)
            [ -n "$CONTAINERS" ] && docker stop $CONTAINERS 2>/dev/null
            systemctl stop docker 2>/dev/null
            if grep -q " /var/lib/docker " /proc/mounts; then
                if ! umount /var/lib/docker; then
                    echo "Failed to umount /var/lib/docker; skipping reformat" > /dev/tty2
                    while :; do sleep 2; done
                fi
            fi
            DOCKER_PART="/dev/disk/by-label/docker"
            [ -b "$DOCKER_PART" ] && mkfs.ext4 -F -L docker "$DOCKER_PART"
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

        # Atomic consume: rename in one step rather than `[ -f ] && rm` so a
        # concurrent systemMonitor recreate cannot be lost between the check
        # and the delete.
        if mv /tmp/SYSTEM_STABLE /tmp/.SYSTEM_STABLE.consumed 2>/dev/null; then
            echo "Container status is ok"  > /dev/tty2
            rm -f /tmp/.SYSTEM_STABLE.consumed
            COUNTER=0
            LAST_CHANCE=0
        fi

    fi

    echo "1" >&4

    sleep 1

done
