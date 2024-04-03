#!/bin/bash

echo "JSDELIV AUTO Update start" > /dev/tty5

echo "STOPING the MANDATORY reboot script" > /dev/tty5
killall -STOP jsdelivr-mandatoryReboot.sh
killall -STOP jsdelivr-systemMonitor.sh


killall  -9 jsdelivr-systemWatchdog.sh
sleep 1
/usr/bin/jsdelivr-keepWatchdogHappy.sh &

docker stop $(docker ps -a -q)
/bin/systemctl stop containerd
/bin/systemctl stop docker
umount /var/lib/docker/overlay2/*/*
umount /var/lib/docker
echo 1 > /sys/block/zram0/reset


mkdir /tmp/AutoUpdate
mount -o ro /dev/mmcblk0p4 /tmp/AutoUpdate

if mount | grep "/tmp/AutoUpdate" > /dev/null; then
    echo "Partition mounted" > /dev/tty5
else
    echo "Unable to mount autoupdate partition, Aborting update" > /dev/tty5
    echo "Resuming the MANDATORY reboot script" > /dev/tty5
    killall -CONT jsdelivr-mandatoryReboot.sh
    killall jsdelivr-keepWatchdogHappy.sh
    exit 1
fi

SERVER_VER=`curl --silent https://data.jsdelivr.com/v1/packages/gh/jsdelivr/globalping-probe/resolved   | awk -F ':'  '/"version"/ {print  substr($NF, 1, length($NF)-1)}'`
CURRENT_VER=`cat /tmp/AutoUpdate/CURRENT_VERSION`

echo "VERSIONS:" > /dev/tty5
echo "SERVER_VERSION: $SERVER_VER" > /dev/tty5
echo "CURRENT_VERSION: $CURRENT_VER" > /dev/tty5


if [ "$SERVER_VER" = "$CURRENT_VER" ]; then
    echo "The version are the same... aborting upgrade and waiting for the next upgrade cycle" > /dev/tty5
    echo "Resuming the MANDATORY reboot script" > /dev/tty5
    killall -CONT jsdelivr-mandatoryReboot.sh
    killall -CONT jsdelivr-systemMonitor.sh
    killall jsdelivr-keepWatchdogHappy.sh
    exit 2
fi


if [ -f /tmp/CAN_UPGRADE ]; then
    echo "Can Upgrade flag is present" > /dev/tty5
    if [ -f /JSDELIVR_BASE_CONTAINER/VERSION ]; then
        echo "The bundled container can be upgraded " > /dev/tty5
        mkdir /tmp/rfs
        mount  /dev/mmcblk0p2 /tmp/rfs
        mount -o remount,rw /tmp/rfs
        rm /tmp/rfs/JSDELIVR_BASE_CONTAINER/globalping-probe.frozen
        date >> /tmp/rfs/JSDELIVR_BASE_CONTAINER/AUTO_UPDATE
        cp /JSDELIVR_BASE_CONTAINER/VERSION /tmp/rfs/JSDELIVR_BASE_CONTAINER
        cp /JSDELIVR_BASE_CONTAINER/globalping-probe.frozen /tmp/rfs/JSDELIVR_BASE_CONTAINER/globalping-probe.frozen
        umount /tmp/rfs
        mount -o remount,rw /JSDELIVR_BASE_CONTAINER
        rm /JSDELIVR_BASE_CONTAINER/VERSION
        echo "The bundled container was upgraded" > /dev/tty5
    else
        echo "The bundled container cant be upgraded" > /dev/tty5
    fi
else
    echo "Can Upgrade flag is NOT present" > /dev/tty5
fi


umount /JSDELIVR_BASE_CONTAINER
mount -o remount,rw /tmp/AutoUpdate
mkdir /tmp/AutoUpdate/download

echo "Initiate image download" > /dev/tty5

skopeo --override-arch arm copy docker://globalping/globalping-probe:latest docker-archive:/tmp/AutoUpdate/globalping-probe.frozen:globalping-probe

echo "Image download FINISHED" > /dev/tty5


echo "Start main image repo update" > /dev/tty5

umount /dev/mmcblk0p3
dd if=/dev/zero of=/dev/mmcblk0p3 bs=1M count=2
mkfs.ext4 /dev/mmcblk0p3
mount /dev/mmcblk0p3 /JSDELIVR_BASE_CONTAINER
cp /tmp/AutoUpdate/globalping-probe.frozen /JSDELIVR_BASE_CONTAINER/globalping-probe.frozen.new
echo "$SERVER_VER" > /tmp/AutoUpdate/CURRENT_VERSION
cp /tmp/AutoUpdate/CURRENT_VERSION /JSDELIVR_BASE_CONTAINER/VERSION
sync
mv /JSDELIVR_BASE_CONTAINER/globalping-probe.frozen.new /JSDELIVR_BASE_CONTAINER/globalping-probe.frozen
mount -o remount,ro /JSDELIVR_BASE_CONTAINER

rm /tmp/AutoUpdate/globalping-probe.frozen
sync

echo "Main image repo update finished" > /dev/tty5



umount /tmp/AutoUpdate

echo "JSDELIV AUTO Update FINISHED" > /dev/tty5
echo "Resuming the MANDATORY reboot script" > /dev/tty5
killall -CONT jsdelivr-mandatoryReboot.sh
killall -CONT jsdelivr-systemMonitor.sh
killall jsdelivr-keepWatchdogHappy.sh
