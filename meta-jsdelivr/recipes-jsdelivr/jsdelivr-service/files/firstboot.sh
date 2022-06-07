HOST_PREFIX=${HOST_PREFIX:-"globalping-probe"}
NET_DEVICE=${NET_DEVICE:="eth0"}
LAST_MAC4=$(sed -rn "s/^.*([0-9A-F:]{5})$/\1/gi;s/://p" /sys/class/net/${NET_DEVICE}/address)
NEW_HOSTNAME=${HOST_PREFIX}-${LAST_MAC4:-0000}

/bin/mount -o remount,rw /

echo $NEW_HOSTNAME > /etc/hostname
/bin/hostname -F /etc/hostname

/bin/mount -o remount,ro /

