#!/bin/bash


export GP_HOST_HW=true
export GP_HOST_DEVICE=v1
export GP_HOST_FIRMWARE=v2.0

echo "Starting JSDELIVR World" > /dev/tty3

echo "panic"  >  /sys/class/leds/nanopi\:green\:pwr/trigger
sleep 2
echo "panic"  >  /sys/class/leds/nanopi\:green\:pwr/trigger

/usr/bin/jsdelivr-firstBoot.sh
/usr/bin/jsdelivr-updateContainer.sh

/usr/bin/jsdelivr-maxPower.sh

/bin/systemctl stop containerd
/bin/systemctl stop docker

echo "Changing compression algo"  > /dev/tty3
echo "zstd" > /sys/block/zram0/comp_algorithm


echo "Change ram disk size"  > /dev/tty3
echo 400M > /sys/block/zram0/mem_limit
echo 800M > /sys/block/zram0/disksize


echo "Formating ram disk"  > /dev/tty3
/sbin/mkfs.ext4 /dev/zram0

echo "Mounting ram disk"  > /dev/tty3
mkdir /var/lib/docker
/bin/mount /dev/zram0 /var/lib/docker


rm -rf /var/run/docker/*
rm -rf  /var/lib/docker/*

/bin/systemctl start containerd
/bin/systemctl start docker


cat /JSDELIVR_BASE_CONTAINER/globalping-probe.frozen  | /usr/bin/docker load > /dev/tty3

/usr/bin/jsdelivr-grabDevLogs.sh &
/usr/bin/jsdelivr-mandatoryReboot.sh  &
/usr/bin/jsdelivr-systemMonitor.sh  &
/usr/bin/jsdelivr-systemWatchdog.sh &


sleep 3

/usr/bin/docker info  > /dev/tty3

echo "Running image/container...."  > /dev/tty3

/usr/bin/jsdelivr-normalPower.sh

while [ 1 ]; do

    RUNNING=$(docker inspect --format='{{.State.Running}}' globalping-probe)

    if [ "$RUNNING" != "true" ]; then
        /usr/bin/docker run -d  --env GP_HOST_HW --env GP_HOST_DEVICE --env GP_HOST_FIRMWARE --log-driver local --log-opt max-size=10m --network host --restart=always --name globalping-probe globalping-probe
    fi

    sleep 10

done
