#!/bin/bash

if [ ! -f /etc/jsdlvr_first_boot_flag  ]
then
    mkdir /tmp/once
    mount /dev/mmcblk0p2 /tmp/once
    mount -o remount,rw /dev/mmcblk0p2 /tmp/once
    cp /etc/machine-id /tmp/once/etc
    touch /tmp/once/etc/jsdlvr_first_boot_flag
    echo "VendorClassIdentifier=globalping-probe" >> /tmp/once/lib/systemd/network/80-wired.network
    echo "LLMNR=no" >> /tmp/once/etc/systemd/resolved.conf
    umount /tmp/once
    echo "mkpart primary ext2 700MB 1200MB" | /usr/sbin/parted /dev/mmcblk0
    sync
    reboot -f
    while :; do  sleep 2; done
fi