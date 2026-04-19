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

       CONTAINERS=$(docker ps -aq 2>/dev/null)
       [ -n "$CONTAINERS" ] && docker stop $CONTAINERS

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

       if [ "$PULL_OK" -eq 0 ]; then
           echo "ERROR: All pull attempts failed for :latest, leaving flag for next boot retry" > /dev/tty4
       else
           rm /tmp/updateFlag/JSDELIVR.UPD
           sync

           reboot
           echo "1" > /dev/watchdog0
           while :; do  sleep 2; done
       fi

   fi

   if [ -f /tmp/updateFlag/JSDELIVR-DEV.UPD ]; then
       echo "DEV UPDATE Flag found!" > /dev/tty4
       echo timer  > /sys/class/leds/user_led/trigger
       echo 50 >   /sys/class/leds/user_led/delay_on
       echo 50 >   /sys/class/leds/user_led/delay_off

       echo "Starting container update process" > /dev/tty4

       CONTAINERS=$(docker ps -aq 2>/dev/null)
       [ -n "$CONTAINERS" ] && docker stop $CONTAINERS

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
           echo "ERROR: All pull attempts failed for :dev, leaving flag for next boot retry" > /dev/tty4
       else
           rm /tmp/updateFlag/JSDELIVR-DEV.UPD
           sync

           reboot
           echo "1" > /dev/watchdog0
           while :; do  sleep 2; done
       fi

   fi



   if [ -f /tmp/updateFlag/JSDELIVR.RESET ]; then
      echo "Erase container update" > /dev/tty4

      CONTAINERS=$(docker ps -aq 2>/dev/null)
      [ -n "$CONTAINERS" ] && docker stop $CONTAINERS
      systemctl stop docker

      if grep -q " /var/lib/docker " /proc/mounts; then
          if ! umount /var/lib/docker; then
              echo "ERROR: Failed to unmount /var/lib/docker" > /dev/tty4
              exit 1
          fi
      fi

      # Reset Docker storage (p6=docker) - NOT p5 which is persist
      # A/B layout: p3=rootfs-a, p4=rootfs-b, p5=persist, p6=docker, p7=docker_persist
      DOCKER_PART="/dev/disk/by-label/docker"
      if [ -b "$DOCKER_PART" ]; then
          if ! mkfs.ext4 -F -L docker "$DOCKER_PART"; then
              echo "ERROR: Failed to format docker partition" > /dev/tty4
              exit 1
          fi
      else
          echo "ERROR: Docker partition not found" > /dev/tty4
          exit 1
      fi

      if ! mount "$DOCKER_PART" /var/lib/docker; then
          echo "ERROR: Failed to mount docker partition" > /dev/tty4
          exit 1
      fi

      rm /tmp/updateFlag/JSDELIVR.RESET

      systemctl start docker
      sleep 5

      # Load frozen image. Warn but proceed on failure — startWorld.sh's
      # init_docker_repo path will retry the load on next boot.
      if [ -s /JSDELIVR_BASE_CONTAINER/globalping-probe.frozen ]; then
          if ! /usr/bin/docker load < /JSDELIVR_BASE_CONTAINER/globalping-probe.frozen > /dev/tty3; then
              echo "WARNING: docker load failed; startWorld.sh will reinit on next boot" > /dev/tty4
          fi
      else
          echo "WARNING: frozen container missing; startWorld.sh will reinit on next boot" > /dev/tty4
      fi

      sleep 5

      reboot
      echo "1" > /dev/watchdog0
      while :; do  sleep 2; done

   fi

fi

