#!/bin/bash

# Source shared utilities
source /usr/bin/jsdelivr-utils.sh

# Detect boot device (SD card = mmcblk0, eMMC = mmcblk2)
detect_boot_device

echo "JSDELIVR Update start" > /dev/tty4




if [ -b /dev/sda1 ]; then
   echo "Usb drive mount found!" > /dev/tty4
   if [ -f /tmp/updateFlag/JSDELIVR.UPD ]; then
       echo "UPDATE Flag found!" > /dev/tty4
       echo timer  > /sys/class/leds/user_led/trigger
       echo 50 >   /sys/class/leds/user_led/delay_on
       echo 50 >   /sys/class/leds/user_led/delay_off

       docker stop $(docker ps -a -q)

       # Retry docker pull with backoff (network may not be ready)
       PULL_OK=0
       for ATTEMPT in 1 2 3; do
           echo "Pull attempt $ATTEMPT/3 for :latest" > /dev/tty4
           if docker pull globalping/globalping-probe:latest; then
               PULL_OK=1
               break
           fi
           echo "Pull failed, waiting $((ATTEMPT * 10))s before retry" > /dev/tty4
           sleep $((ATTEMPT * 10))
       done
       rm /tmp/updateFlag/JSDELIVR.UPD

       if [ "$PULL_OK" -eq 0 ]; then
           echo "ERROR: All pull attempts failed for :latest, skipping reboot" > /dev/tty4
       else
           sync

           reboot
           echo "1" > /dev/watchdog
           while :; do  sleep 2; done
       fi

   fi

   if [ -f /tmp/updateFlag/JSDELIVR-DEV.UPD ]; then
       echo "DEV UPDATE Flag found!" > /dev/tty4
       echo timer  > /sys/class/leds/user_led/trigger
       echo 50 >   /sys/class/leds/user_led/delay_on
       echo 50 >   /sys/class/leds/user_led/delay_off

       rm /tmp/updateFlag/JSDELIVR-DEV.UPD
       sync

       echo "Starting container update process" > /dev/tty4

       docker stop $(docker ps -a -q)

       # Retry docker pull with backoff (network may not be ready)
       PULL_OK=0
       for ATTEMPT in 1 2 3; do
           echo "Pull attempt $ATTEMPT/3 for :dev" > /dev/tty4
           if docker pull globalping/globalping-probe:dev; then
               PULL_OK=1
               break
           fi
           echo "Pull failed, waiting $((ATTEMPT * 10))s before retry" > /dev/tty4
           sleep $((ATTEMPT * 10))
       done
       if [ "$PULL_OK" -eq 0 ]; then
           echo "ERROR: All pull attempts failed for :dev, skipping reboot" > /dev/tty4
       else
           reboot
           echo "1" > /dev/watchdog
           while :; do  sleep 2; done
       fi

   fi



   if [ -f /tmp/updateFlag/JSDELIVR.RESET ]; then
      echo "Erase container update" > /dev/tty4

      docker stop $(docker ps -a -q)
      systemctl stop docker

      umount /var/lib/docker

      # Reset Docker storage (p6=docker) - NOT p5 which is persist
      # A/B layout: p3=rootfs-a, p4=rootfs-b, p5=persist, p6=docker, p7=docker_persist
      DOCKER_PART="/dev/disk/by-label/docker"
      if [ -b "$DOCKER_PART" ]; then
          mkfs.ext4 -F "$DOCKER_PART"
      fi

      mount "$DOCKER_PART" /var/lib/docker

      rm /tmp/updateFlag/JSDELIVR.RESET

      systemctl start docker
      sleep 5

      cat /JSDELIVR_BASE_CONTAINER/globalping-probe.frozen | /usr/bin/docker load > /dev/tty3

      sleep 5

      reboot
      echo "1" > /dev/watchdog
      while :; do  sleep 2; done

   fi

fi

