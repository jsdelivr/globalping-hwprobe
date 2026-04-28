#!/bin/bash
#
# jsdelivr-firstBoot.sh - First boot initialization for Globalping Probe
#
# This script handles DEVICE IDENTITY generation and partition setup.
# It runs only once per device (flag stored on persist partition).
#
# Static configs (network, DNS, NTP) are now baked into the image via
# jsdelivr-configure recipe - no runtime modification needed for A/B updates.
#
# Device identity (UUID, SSH keys, machine-id) is stored on /persist partition
# which is shared between A/B slots. The RAUC post-install handler copies
# identity to new slots during OTA updates.
#

# Log function - outputs to both tty3 and console for debugging
log() {
    echo "First boot: $1" | tee /dev/console > /dev/tty3 2>/dev/null || echo "First boot: $1"
}

log "Script starting..."

# Source shared utilities
if [ -f /usr/bin/jsdelivr-utils.sh ]; then
    source /usr/bin/jsdelivr-utils.sh
    log "Sourced jsdelivr-utils.sh"
else
    log "ERROR: /usr/bin/jsdelivr-utils.sh not found!"
    exit 1
fi

# Detect boot device (SD card = mmcblk0, eMMC = mmcblk2)
detect_boot_device
log "Detected boot device: $BOOT_DEVICE"

# Partition layout for A/B updates:
# p3=rootfs-a, p4=rootfs-b, p5=persist, p6=docker, p7=docker_persist
FIRST_BOOT_FLAG="jsdelivr-first-boot-complete"
FIRST_BOOT_INPROGRESS_FLAG="jsdelivr-first-boot-in-progress"
IDENTITY_DIR="device-identity"

# The persist partition is mounted at /persist by fstab (using LABEL=persist)
# This is more reliable than trying to mount by device path
PERSIST_MOUNT="/persist"

# Wait for /persist to be mounted by systemd (up to 30 seconds)
log "Waiting for /persist to be mounted..."
WAIT_COUNT=0
while [ ! -d "$PERSIST_MOUNT" ] || ! mountpoint -q "$PERSIST_MOUNT" 2>/dev/null; do
    if [ $WAIT_COUNT -ge 30 ]; then
        log "ERROR - /persist not mounted after 30 seconds"
        log "Current mounts:"
        mount | tee /dev/console > /dev/tty3 2>/dev/null || mount
        exit 1
    fi
    sleep 1
    WAIT_COUNT=$((WAIT_COUNT + 1))
done
log "/persist is mounted (waited ${WAIT_COUNT}s)"

# Debug: show mount info
log "Mount info for /persist:"
mount | grep persist | tee /dev/console > /dev/tty3 2>/dev/null || true
df -h /persist 2>/dev/null | tee /dev/console > /dev/tty3 2>/dev/null || true

# Check if first boot already completed
FIRST_BOOT_DONE=false
if [ -f "${PERSIST_MOUNT}/${FIRST_BOOT_FLAG}" ]; then
    FIRST_BOOT_DONE=true
    log "Already completed (flag found on persist partition)"
    log "Exiting without reboot"
    exit 0
fi

# A previous run started but did not complete (script crashed mid-init, power
# loss, etc.). Re-running blindly would re-execute destructive ops like
# parted, mkfs, and overwriting extlinux.conf on the inactive slot. Refuse to
# proceed automatically — operator must clear the flag to retry.
if [ -f "${PERSIST_MOUNT}/${FIRST_BOOT_INPROGRESS_FLAG}" ]; then
    log "FATAL - previous first-boot run did not complete (in-progress flag present)"
    log "Operator must investigate and remove ${PERSIST_MOUNT}/${FIRST_BOOT_INPROGRESS_FLAG} to retry"
    log "Halting to prevent partition / extlinux corruption"
    exit 1
fi

log "First boot detected - starting device initialization..."

# Mark in progress before any destructive op so a crash leaves a tombstone.
log "Remounting /persist rw to write in-progress marker..."
if ! mount -o remount,rw /persist; then
    log "FATAL - Failed to remount /persist as read-write!"
    log "NOT rebooting to prevent reboot loop"
    exit 1
fi
touch "${PERSIST_MOUNT}/${FIRST_BOOT_INPROGRESS_FLAG}"
sync

# Detect which RAUC slot we booted from (a or b)
RAUC_SLOT=$(grep -o 'rauc\.slot=[ab]' /proc/cmdline | cut -d= -f2)
RAUC_SLOT=${RAUC_SLOT:-a}
log "Detected RAUC slot: $RAUC_SLOT"

# Determine rootfs partition based on slot
if [ "$RAUC_SLOT" = "b" ]; then
    ROOTFS_PART="p4"
else
    ROOTFS_PART="p3"
fi
log "Using rootfs partition: ${BOOT_DEVICE}${ROOTFS_PART}"

# =========================================================================
# STEP 1: Generate device identity and store on persist partition
# =========================================================================
log "STEP 1: Generating device identity..."

# /persist is mounted read-only by default for safety
# Remount as read-write temporarily to make changes
log "Remounting /persist as read-write..."
if ! mount -o remount,rw /persist; then
    log "FATAL - Failed to remount /persist as read-write!"
    log "Current mount status:"
    mount | grep persist | tee /dev/console > /dev/tty3 2>/dev/null || true
    log "NOT rebooting to prevent reboot loop"
    exit 1
fi
log "Remounted /persist as read-write"

# Create identity directory
log "Creating identity directories..."
mkdir -p ${PERSIST_MOUNT}/${IDENTITY_DIR}
mkdir -p ${PERSIST_MOUNT}/${IDENTITY_DIR}/ssh
mkdir -p ${PERSIST_MOUNT}/jsdelivr-config
mkdir -p ${PERSIST_MOUNT}/container-overrides
mkdir -p ${PERSIST_MOUNT}/rauc

# Generate probe UUID (only if not already exists)
if [ ! -f ${PERSIST_MOUNT}/${IDENTITY_DIR}/muid.data ]; then
    if command -v uuidgen >/dev/null; then
        MUID="$(uuidgen -r | tr '[:upper:]' '[:lower:]')"
    else
        MUID="$(cat /proc/sys/kernel/random/uuid)"
    fi
    echo "GP_PROBE_UUID=$MUID" > ${PERSIST_MOUNT}/${IDENTITY_DIR}/muid.data
    log "Generated probe UUID: $MUID"
else
    log "Probe UUID already exists on persist"
fi

# Generate SSH host keys (only if not already exists)
if [ ! -f ${PERSIST_MOUNT}/${IDENTITY_DIR}/ssh/ssh_host_rsa_key ]; then
    log "Generating SSH host keys..."
    /usr/libexec/openssh/sshd_check_keys 2>/dev/null || true
    cp /var/run/ssh/* ${PERSIST_MOUNT}/${IDENTITY_DIR}/ssh/ 2>/dev/null || true
    log "SSH keys stored on persist partition"
else
    log "SSH keys already exist on persist"
fi

# Store machine-id (only if not already exists)
if [ ! -f ${PERSIST_MOUNT}/${IDENTITY_DIR}/machine-id ]; then
    cp /etc/machine-id ${PERSIST_MOUNT}/${IDENTITY_DIR}/machine-id 2>/dev/null || true
    log "Machine ID stored on persist partition"
else
    log "Machine ID already exists on persist"
fi

sync
log "Device identity saved to persist partition"

# =========================================================================
# STEP 2: Copy identity from persist to current rootfs
# =========================================================================
log "STEP 2: Copying identity to current rootfs..."

# The rootfs is already mounted at / (read-only)
# We need to remount it as read-write to copy identity files
log "Remounting / as read-write..."
if mount -o remount,rw /; then
    log "Remounted / as read-write"

    # Copy muid.data
    if [ -f ${PERSIST_MOUNT}/${IDENTITY_DIR}/muid.data ]; then
        cp ${PERSIST_MOUNT}/${IDENTITY_DIR}/muid.data /etc/muid.data
        log "Copied muid.data to /etc/"
    fi

    # Copy machine-id
    if [ -f ${PERSIST_MOUNT}/${IDENTITY_DIR}/machine-id ]; then
        cp ${PERSIST_MOUNT}/${IDENTITY_DIR}/machine-id /etc/machine-id
        log "Copied machine-id to /etc/"
    fi

    # Copy SSH keys
    if [ -d ${PERSIST_MOUNT}/${IDENTITY_DIR}/ssh ]; then
        mkdir -p /etc/ssh/keys
        cp ${PERSIST_MOUNT}/${IDENTITY_DIR}/ssh/* /etc/ssh/keys/ 2>/dev/null || true
        # Update sshd config to use keys from /etc/ssh/keys/
        if [ -f /etc/ssh/sshd_config_readonly ]; then
            sed -i 's|/var/run/ssh/|/etc/ssh/keys/|g' /etc/ssh/sshd_config_readonly 2>/dev/null || true
        fi
        log "Copied SSH keys to /etc/ssh/keys/"
    fi

    sync

    # Remount / back to read-only
    log "Remounting / as read-only..."
    mount -o remount,ro / || log "WARNING: Failed to remount / as read-only"
else
    log "WARNING: Failed to remount / as read-write, skipping identity copy to rootfs"
fi

# =========================================================================
# STEP 3: Create docker partitions (dynamic based on disk size)
# =========================================================================
log "STEP 3: Setting up docker partitions on /dev/${BOOT_DEVICE}"

# Check if docker partitions already exist (idempotent - safe to re-run)
if [ -b "/dev/disk/by-label/docker" ] && [ -b "/dev/disk/by-label/docker_persist" ]; then
    log "Docker partitions already exist (labels found), skipping creation"
else
    # Fix GPT table to use all available space
    parted /dev/${BOOT_DEVICE} --script --fix print 2>/dev/null || true

    # Get disk size in MB
    DISK_SIZE_MB=$(parted /dev/${BOOT_DEVICE} --script -- unit MB print | grep "^Disk /dev/${BOOT_DEVICE}" | awk '{print $3}' | sed 's/MB//')

    # Find the last partition number and its end position
    LAST_PART_NUM=$(parted /dev/${BOOT_DEVICE} --script -- unit MB print | grep "^ " | awk '{print $1}' | sort -n | tail -1)
    LAST_PART_END=$(parted /dev/${BOOT_DEVICE} --script -- unit MB print | grep "^ ${LAST_PART_NUM}" | awk '{print $3}' | sed 's/MB//')

    log "Last partition is ${LAST_PART_NUM}, ends at ${LAST_PART_END}MB, disk size ${DISK_SIZE_MB}MB"

    # Calculate next partition numbers
    DOCKER_PART_NUM=$((LAST_PART_NUM + 1))
    DOCKER_PERSIST_PART_NUM=$((LAST_PART_NUM + 2))

    # Calculate partition sizes (only if we have enough space)
    if [ -n "$DISK_SIZE_MB" ] && [ -n "$LAST_PART_END" ]; then
        AVAILABLE_MB=$((DISK_SIZE_MB - LAST_PART_END))
        log "Available space: ${AVAILABLE_MB}MB"

        if [ "$AVAILABLE_MB" -gt 1000 ]; then
            # Docker partition: Half of remaining space
            DOCKER_START="${LAST_PART_END}"
            DOCKER_END=$((LAST_PART_END + AVAILABLE_MB / 2))

            # Docker persist partition: Remaining space
            DOCKER_PERSIST_START="${DOCKER_END}"
            DOCKER_PERSIST_END=$((DISK_SIZE_MB - 1))

            log "Creating partition ${DOCKER_PART_NUM} (docker) from ${DOCKER_START}MB to ${DOCKER_END}MB"
            parted -a optimal /dev/${BOOT_DEVICE} --script -- mkpart primary ext4 ${DOCKER_START}MB ${DOCKER_END}MB

            log "Creating partition ${DOCKER_PERSIST_PART_NUM} (docker_persist) from ${DOCKER_PERSIST_START}MB to ${DOCKER_PERSIST_END}MB"
            parted -a optimal /dev/${BOOT_DEVICE} --script -- mkpart primary ext4 ${DOCKER_PERSIST_START}MB ${DOCKER_PERSIST_END}MB

            partprobe /dev/${BOOT_DEVICE}
            sleep 2

            log "Formatting partition ${DOCKER_PART_NUM} (docker) as ext4"
            mkfs.ext4 -F -L docker /dev/${BOOT_DEVICE}p${DOCKER_PART_NUM}
            log "Formatting partition ${DOCKER_PERSIST_PART_NUM} (docker_persist) as ext4"
            mkfs.ext4 -F -L docker_persist /dev/${BOOT_DEVICE}p${DOCKER_PERSIST_PART_NUM}

            # Create subdirectories on docker_persist partition
            log "Creating subdirectories on docker_persist"
            mkdir -p /tmp/docker_persist
            if mount /dev/${BOOT_DEVICE}p${DOCKER_PERSIST_PART_NUM} /tmp/docker_persist; then
                mkdir -p /tmp/docker_persist/wireguard
                mkdir -p /tmp/docker_persist/speedtest
                umount /tmp/docker_persist
            fi
            rmdir /tmp/docker_persist 2>/dev/null
            log "Docker partitions created successfully"
        else
            log "Not enough space for Docker partitions (only ${AVAILABLE_MB}MB available)"
        fi
    else
        log "Could not determine disk size, skipping partition creation"
    fi
fi

# =========================================================================
# STEP 3b: Fix inactive slot's extlinux.conf for RAUC A/B boot
# =========================================================================
# Both rootfs-a and rootfs-b are flashed with identical images, but each
# slot needs its own extlinux.conf pointing to its own PARTLABEL and rauc.slot.
# The active slot (booted now) is correct. Fix the inactive slot.
if [ "$RAUC_SLOT" = "a" ]; then
    INACTIVE_PART="/dev/${BOOT_DEVICE}p4"
    INACTIVE_SLOT="b"
else
    INACTIVE_PART="/dev/${BOOT_DEVICE}p3"
    INACTIVE_SLOT="a"
fi

log "Fixing extlinux.conf on inactive slot ${INACTIVE_SLOT} (${INACTIVE_PART})..."
INACTIVE_MOUNT="/tmp/rauc-inactive"
mkdir -p "$INACTIVE_MOUNT"
if mount "$INACTIVE_PART" "$INACTIVE_MOUNT" 2>/dev/null; then
    if [ -d "$INACTIVE_MOUNT/boot/extlinux" ]; then
        cat > "$INACTIVE_MOUNT/boot/extlinux/extlinux.conf.tmp" <<EXTEOF
# Extlinux configuration for NanoPi Zero2 (RAUC A/B Boot - Slot ${INACTIVE_SLOT})
# Auto-generated by firstBoot.sh
label Yocto Linux Slot ${INACTIVE_SLOT}
    kernel /boot/Image
    fdt /boot/rk3528-nanopi-rev01.dtb
    append root=PARTLABEL=rootfs-${INACTIVE_SLOT} rauc.slot=${INACTIVE_SLOT} rootwait rootfstype=ext4 console=ttyFIQ0,1500000n8 earlycon=uart8250,mmio32,0xff9f0000
EXTEOF
        mv "$INACTIVE_MOUNT/boot/extlinux/extlinux.conf.tmp" "$INACTIVE_MOUNT/boot/extlinux/extlinux.conf"
        log "Updated extlinux.conf for slot ${INACTIVE_SLOT}"
    else
        log "WARNING: No boot/extlinux directory on inactive slot"
    fi
    # Copy device identity to inactive slot too
    if [ -f "${PERSIST_MOUNT}/${IDENTITY_DIR}/muid.data" ]; then
        cp "${PERSIST_MOUNT}/${IDENTITY_DIR}/muid.data" "$INACTIVE_MOUNT/etc/muid.data" 2>/dev/null || true
    fi
    if [ -f "${PERSIST_MOUNT}/${IDENTITY_DIR}/machine-id" ]; then
        cp "${PERSIST_MOUNT}/${IDENTITY_DIR}/machine-id" "$INACTIVE_MOUNT/etc/machine-id" 2>/dev/null || true
    fi
    if [ -d "${PERSIST_MOUNT}/${IDENTITY_DIR}/ssh" ]; then
        mkdir -p "$INACTIVE_MOUNT/etc/ssh/keys"
        cp "${PERSIST_MOUNT}/${IDENTITY_DIR}/ssh/"* "$INACTIVE_MOUNT/etc/ssh/keys/" 2>/dev/null || true
    fi
    sync
    umount "$INACTIVE_MOUNT"
    log "Inactive slot ${INACTIVE_SLOT} ready for rollback"
else
    log "WARNING: Could not mount inactive slot ${INACTIVE_PART}"
fi
rmdir "$INACTIVE_MOUNT" 2>/dev/null

# =========================================================================
# STEP 4: Create completion flag and reboot
# =========================================================================
log "STEP 4: Creating completion flag and preparing to reboot..."

# /persist may have been remounted by systemd during STEP 3
# Ensure it's read-write before creating the flag
log "Ensuring /persist is read-write..."
if ! mount -o remount,rw /persist 2>/dev/null; then
    log "WARNING: Could not remount /persist as read-write, trying anyway..."
fi

if touch "${PERSIST_MOUNT}/${FIRST_BOOT_FLAG}"; then
    log "Created completion flag on persist partition"
    # Clear the in-progress tombstone now that we've reached completion
    rm -f "${PERSIST_MOUNT}/${FIRST_BOOT_INPROGRESS_FLAG}"
    sync
    # Remount /persist back to read-only for safety
    mount -o remount,ro /persist
    log "Remounted /persist as read-only"
else
    log "FATAL - Could not create completion flag!"
    log "NOT rebooting to prevent reboot loop"
    # Try to remount read-only anyway
    mount -o remount,ro /persist 2>/dev/null
    exit 1
fi

log "=========================================="
log "Initialization complete, REBOOTING NOW..."
log "=========================================="
sync
sleep 1
reboot -f
# Ensure we don't continue if reboot fails
while :; do sleep 2; done
