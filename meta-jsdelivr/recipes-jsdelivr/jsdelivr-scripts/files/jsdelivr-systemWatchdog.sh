#!/bin/bash

COUNTER=0
(( TTL_MAX= 60 * 5  ))
LAST_CHANCE=0
LIMIT=0
exec 4> /dev/watchdog1


while [ 1 ];
do
    COUNTER=$((COUNTER+1))
    echo "System WatchDog counter:$COUNTER Max:$TTL_MAX LAST_CHANCE:$LAST_CHANCE" > /dev/tty2
    if [ "$COUNTER" -gt "$TTL_MAX" ]; then
        echo "Container status is faulty" > /dev/tty2
        if [ "$LAST_CHANCE" -gt "$LIMIT" ]; then
            echo "Container recover attempt failed, resorting to full system reboot"  > /dev/tty2

            umount /JSDELIVR_BASE_CONTAINER
            dd if=/dev/zero of=/dev/mmcblk0p3 bs=10M count=1
            umount /dev/mmcblk0p4
            mkfs.ext4 /dev/mmcblk0p4
            while :; do  sleep 2; done
        fi
        echo "1" >&4
        echo "Trying to recover container"  > /dev/tty2
        docker kill  globalping-probe
        echo "1" >&4
        docker kill  globalping-probe
        echo "1" >&4
        docker ps -a > /dev/tty2 > /dev/tty2
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
