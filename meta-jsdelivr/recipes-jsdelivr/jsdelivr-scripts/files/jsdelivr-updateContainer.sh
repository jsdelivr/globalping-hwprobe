#!/bin/bash

# Source shared utilities
source /usr/bin/jsdelivr-utils.sh

# Detect boot device (SD card = mmcblk0, eMMC = mmcblk2)
detect_boot_device

echo "JSDELIVR Update start" > /dev/tty4

# USB-stick container update flow:
#   user creates one of these files at the root of a USB stick partition,
#   inserts the stick, and reboots. We mount whichever USB partition we find,
#   read the flag from there, and on success delete the flag from the stick
#   so subsequent boots do not re-trigger.
#
# Supported flag files (root of the USB partition):
#   JSDELIVR.UPD        -> docker pull globalping-probe:latest
#   JSDELIVR-DEV.UPD    -> docker pull globalping-probe:dev
#   JSDELIVR.RESET      -> wipe and reformat the docker partition
USB_MOUNT="/run/usb-update"

# Find the first USB partition node. Prefer /dev/sda1 for backwards
# compatibility, but fall through to anything matching sd?[0-9].
USB_DEV=""
for cand in /dev/sda1 /dev/sdb1 /dev/sdc1 /dev/sda2 /dev/sdb2; do
    [ -b "$cand" ] && USB_DEV="$cand" && break
done
if [ -z "$USB_DEV" ]; then
    for cand in /dev/sd?[0-9]; do
        [ -b "$cand" ] && USB_DEV="$cand" && break
    done
fi

if [ -z "$USB_DEV" ]; then
    echo "No USB drive present, skipping USB update check" > /dev/tty4
    exit 0
fi

echo "USB drive detected: $USB_DEV" > /dev/tty4

# Mount RW so we can clear the flag on success. Let the kernel auto-detect
# the filesystem (vfat/exfat/ext4 are all common on USB sticks).
mkdir -p "$USB_MOUNT"
if ! mount "$USB_DEV" "$USB_MOUNT" 2>/dev/null; then
    echo "Could not mount $USB_DEV, skipping USB update check" > /dev/tty4
    rmdir "$USB_MOUNT" 2>/dev/null || true
    exit 0
fi

cleanup_usb() {
    sync
    umount "$USB_MOUNT" 2>/dev/null || true
    rmdir "$USB_MOUNT" 2>/dev/null || true
}
trap cleanup_usb EXIT

if [ -f "$USB_MOUNT/JSDELIVR.UPD" ]; then
   echo "UPDATE Flag found on $USB_DEV" > /dev/tty4
   led_container_starting

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
       rm -f "$USB_MOUNT/JSDELIVR.UPD"
       cleanup_usb
       trap - EXIT

       reboot
       echo "1" > /dev/watchdog0
       while :; do  sleep 2; done
   fi
fi

if [ -f "$USB_MOUNT/JSDELIVR-DEV.UPD" ]; then
   echo "DEV UPDATE Flag found on $USB_DEV" > /dev/tty4
   led_container_starting

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
       rm -f "$USB_MOUNT/JSDELIVR-DEV.UPD"
       cleanup_usb
       trap - EXIT

       reboot
       echo "1" > /dev/watchdog0
       while :; do  sleep 2; done
   fi
fi

if [ -f "$USB_MOUNT/JSDELIVR.RESET" ]; then
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

   rm -f "$USB_MOUNT/JSDELIVR.RESET"

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

   cleanup_usb
   trap - EXIT

   reboot
   echo "1" > /dev/watchdog0
   while :; do  sleep 2; done
fi
