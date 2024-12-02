#!/bin/bash

if [ ! -f /etc/jsdlvr_first_boot_flag  ]
then
    mkdir /tmp/once
    mount /dev/mmcblk0p2 /tmp/once
    mount -o remount,rw /dev/mmcblk0p2 /tmp/once
    cp /etc/machine-id /tmp/once/etc
    export MUID=$(dd if=/dev/urandom bs=16 count=1 2>/dev/null | od -An -t x1 | \
    awk '{
	# Read bytes into an array
	for(i=1; i<=NF; i++) {
    	    byte = strtonum("0x"$i)
    	    bytes[i] = byte
	}
	bytes[7] = and(bytes[7], 0x0F)
	bytes[7] = or(bytes[7], 0x40)
	bytes[9] = and(bytes[9], 0x3F)
	bytes[9] = or(bytes[9], 0x80)
	printf("%02x%02x%02x%02x-%02x%02x-%02x%02x-%02x%02x-%02x%02x%02x%02x%02x%02x\n",
    	    bytes[1], bytes[2], bytes[3], bytes[4],
    	    bytes[5], bytes[6],
    	    bytes[7], bytes[8],
    	    bytes[9], bytes[10],
    	    bytes[11], bytes[12], bytes[13], bytes[14], bytes[15], bytes[16])
	}'
    )

    echo "GP_PROBE_UUID=$MUID" > /tmp/once/etc/muid.data
    echo "VendorClassIdentifier=globalping-probe" >> /tmp/once/lib/systemd/network/80-wired.network
    echo "LLMNR=no" >> /tmp/once/etc/systemd/resolved.conf
    echo "NTP=pool.ntp.org" >> /tmp/once/etc/systemd/timesyncd.conf
    mkdir -p /tmp/once/etc/ssh/keys
    /usr/libexec/openssh/sshd_check_keys
    cp /var/run/ssh/* /tmp/once/etc/ssh/keys
    sed -i 's\/var/run/ssh/\/etc/ssh/keys/\g' sshd_config_readonly /tmp/once/etc/ssh/sshd_config_readonly

    echo "mkpart primary ext2 900MB 1800MB" | /usr/sbin/parted /dev/mmcblk0
    echo "mkpart primary ext2 1900MB 2900MB" | /usr/sbin/parted /dev/mmcblk0

    mkfs.ext4 /dev/mmcblk0p4
    sync
    touch /tmp/once/etc/jsdlvr_first_boot_flag
    umount /tmp/once

    dd if=/dev/zero of=/dev/mmcblk0p3 bs=10M count=1

    reboot -f
    while :; do  sleep 2; done
fi