#!/bin/bash

if [ ! -f /etc/jsdlvr_first_boot_flag  ]
then
    mkdir /tmp/once
    mount /dev/mmcblk0p2 /tmp/once
    mount -o remount,rw /dev/mmcblk0p2 /tmp/once
    cp /etc/machine-id /tmp/once/etc
    echo "VendorClassIdentifier=globalping-probe" >> /tmp/once/lib/systemd/network/80-wired.network
    echo "LLMNR=no" >> /tmp/once/etc/systemd/resolved.conf
    echo "NTP=pool.ntp.org" >> /tmp/once/etc/systemd/timesyncd.conf
    mkdir -p /tmp/once/etc/ssh/keys
    /usr/libexec/openssh/sshd_check_keys
    cp /var/run/ssh/* /tmp/once/etc/ssh/keys
    sed -i 's\/var/run/ssh/\/etc/ssh/keys/\g' sshd_config_readonly /tmp/once/etc/ssh/sshd_config_readonly

    echo "mkpart primary ext2 700MB 1200MB" | /usr/sbin/parted /dev/mmcblk0
    echo "mkpart primary ext2 1200MB 2200MB" | /usr/sbin/parted /dev/mmcblk0
    mkfs.ext4 /dev/mmcblk0p4
    sync
    touch /tmp/once/etc/jsdlvr_first_boot_flag
    umount /tmp/once

    reboot -f
    while :; do  sleep 2; done
fi