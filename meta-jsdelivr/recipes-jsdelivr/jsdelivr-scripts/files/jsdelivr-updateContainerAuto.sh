#!/bin/bash




DAYS=1
RANDOM_OFFSET_DAYS=1



((RANDOM_OFFSET_MAX= 24*60*60*$RANDOM_OFFSET_DAYS))

((UPGRADE_PERIOD_BASE= 24*60*60*$DAYS))

((RANDOM_OFFSET= $RANDOM % $RANDOM_OFFSET_MAX ))

((UPGRADE_PERIOD= $UPGRADE_PERIOD_BASE + $RANDOM_OFFSET ))


echo "Upgrade random offset is $RANDOM_OFFSET seconds" > /dev/tty5
echo "Upgrade period base is $UPGRADE_PERIOD_BASE seconds" > /dev/tty5
echo "Upgrade period is $UPGRADE_PERIOD seconds" > /dev/tty5

while :; do 

    echo "Sleeping...." > /dev/tty5

    sleep $UPGRADE_PERIOD

    echo "It's time...." > /dev/tty5

    echo "JSDELIV AUTO Update start" > /dev/tty5

    echo "STOPING the MANDATORY reboot script" > /dev/tty5
    killall -STOP jsdelivr-mandatoryReboot.sh

    mkdir /tmp/AutoUpdate
    mount -o ro /dev/mmcblk0p4 /tmp/AutoUpdate

    if mount | grep "/tmp/AutoUpdate" > /dev/null; then
        echo "Partition mounted" > /dev/tty5
    else
        echo "Unable to mount autoupdate partition, Aborting update" > /dev/tty5
        echo "Resuming the MANDATORY reboot script" > /dev/tty5
        killall -CONT jsdelivr-mandatoryReboot.sh
        exit 2
    fi

    SERVER_VER=`curl --silent https://api.github.com/repos/jsdelivr/globalping-probe/releases/latest | awk -F ':'  '/"tag_name"/ {print  substr($NF, 1, length($NF)-1)}'`
    CURRENT_VER=`cat /tmp/AutoUpdate/CURRENT_VERSION`

    echo "VERSIONS:" > /dev/tty5
    echo "SERVER_VERSION: $SERVER_VER" > /dev/tty5
    echo "CURRENT_VERSION: $CURRENT_VER" > /dev/tty5

    if [ "$SERVER_VER" = "$CURRENT_VER" ]; then
        echo "The version are the same... aborting upgrade and waiting for the next upgrade cycle" > /dev/tty5
        echo "Resuming the MANDATORY reboot script" > /dev/tty5
        killall -CONT jsdelivr-mandatoryReboot.sh
        continue
    fi

    mount -o remount,rw /tmp/AutoUpdate
    mkdir /tmp/AutoUpdate/download


    /usr/bin/download-frozen-image-v2.sh -d /tmp/AutoUpdate/download  ghcr.io/jsdelivr/globalping-probe
    tar -cC '/tmp/AutoUpdate/download' . | gzip > /tmp/AutoUpdate/globalping-probe.frozen.tar.gz

    umount /JSDELIVR_BASE_CONTAINER
    dd if=/dev/zero of=/dev/mmcblk0p3 bs=1M count=2
    mkfs.ext4 /dev/mmcblk0p3
    mount /dev/mmcblk0p3 /JSDELIVR_BASE_CONTAINER
    cp /tmp/AutoUpdate/globalping-probe.frozen.tar.gz /JSDELIVR_BASE_CONTAINER/globalping-probe.frozen.tar.gz_new
    sync
    mv /JSDELIVR_BASE_CONTAINER/globalping-probe.frozen.tar.gz_new /JSDELIVR_BASE_CONTAINER/globalping-probe.frozen.tar.gz
    mount -o remount,ro /JSDELIVR_BASE_CONTAINER

    rm /tmp/AutoUpdate/globalping-probe.frozen.tar.gz
    sync
    echo "$SERVER_VER" > /tmp/AutoUpdate/CURRENT_VERSION



    umount /tmp/AutoUpdate

    echo "JSDELIV AUTO Update FINISHED" > /dev/tty5
    echo "Resuming the MANDATORY reboot script" > /dev/tty5
    killall -CONT jsdelivr-mandatoryReboot.sh

done
