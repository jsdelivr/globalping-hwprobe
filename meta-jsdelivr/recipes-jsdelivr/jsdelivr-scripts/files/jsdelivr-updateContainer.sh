#!/bin/bash


echo "JSDELIV Update start" > /dev/tty4




if [ -b /dev/sda1 ]; then
   echo "Usb drive mount found!" > /dev/tty4
   mkdir /tmp/updateFlag
   mount /dev/sda1 /tmp/updateFlag
   if [ -f /tmp/updateFlag/JSDELIVR.UPD ]; then
       echo "UPDATE Flag found!" > /dev/tty4
       echo timer  > /sys/class/leds/nanopi\:blue\:status/trigger
       echo 50 >   /sys/class/leds/nanopi\:blue\:status/delay_on
       echo 50 >   /sys/class/leds/nanopi\:blue\:status/delay_off

       rm /tmp/updateFlag/JSDELIVR.UPD
       sync
       umount /tmp/updateFlag
       echo "Starting container update process" > /dev/tty4

       mkfs.ext4 /dev/mmcblk0p3
       mkdir /tmp/updateContainer
       mount /dev/mmcblk0p3 /tmp/updateContainer
       mkdir -p /tmp/updateContainer/globalping-probe.frozen
       /usr/bin/download-frozen-image-v2.sh -d /tmp/updateContainer/globalping-probe.frozen/   ghcr.io/jsdelivr/globalping-probe
       tar -cC '/tmp/updateContainer/globalping-probe.frozen/' . | gzip > /tmp/updateContainer/globalping-probe.frozen.tar.gz
       rm -rf /tmp/updateContainer/globalping-probe.frozen/
       umount /tmp/updateContainer

       sleep 5

       reboot
       echo "1" > /dev/watchdog
       while :; do  sleep 2; done

   fi

   if [ -f /tmp/updateFlag/JSDELIVR-DEV.UPD ]; then
       echo "DEV UPDATE Flag found!" > /dev/tty4
       echo timer  > /sys/class/leds/nanopi\:blue\:status/trigger
       echo 50 >   /sys/class/leds/nanopi\:blue\:status/delay_on
       echo 50 >   /sys/class/leds/nanopi\:blue\:status/delay_off

       rm /tmp/updateFlag/JSDELIVR-DEV.UPD
       sync
       umount /tmp/updateFlag
       echo "Starting container update process" > /dev/tty4

       mkfs.ext4 /dev/mmcblk0p3
       mkdir /tmp/updateContainer
       mount /dev/mmcblk0p3 /tmp/updateContainer
       mkdir -p /tmp/updateContainer/globalping-probe.frozen
       /usr/bin/download-frozen-image-v2.sh -d /tmp/updateContainer/globalping-probe.frozen/  ghcr.io/jsdelivr/globalping-probe:dev
       tar -cC '/tmp/updateContainer/globalping-probe.frozen/' . | gzip > /tmp/updateContainer/globalping-probe.frozen.tar.gz
       rm -rf /tmp/updateContainer/globalping-probe.frozen/
       umount /tmp/updateContainer

       sleep 5

       reboot
       echo "1" > /dev/watchdog
       while :; do  sleep 2; done

   fi



   if [ -f /tmp/updateFlag/JSDELIVR.RESET ]; then
      echo "Erase container update" > /dev/tty4
      dd if=/dev/zero of=/dev/mmcblk0p3 bs=10M count=1
      rm /tmp/updateFlag/JSDELIVR.RESET
      sync
      umount /tmp/updateFlag
      sleep 5

      reboot
      echo "1" > /dev/watchdog
      while :; do  sleep 2; done

   fi

fi


mount -o ro /dev/mmcblk0p3 /JSDELIVR_BASE_CONTAINER
