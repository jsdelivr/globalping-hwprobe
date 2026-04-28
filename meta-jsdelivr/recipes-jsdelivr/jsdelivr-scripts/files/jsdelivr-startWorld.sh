#!/bin/bash

# Source shared utilities (includes LED functions and boot device detection)
source /usr/bin/jsdelivr-utils.sh

# Source muid.data (may not exist on very first boot before firstBoot.sh completes)
# /etc/muid.data uses bare assignment, so source creates a shell variable.
# Must export so `docker run --env GP_PROBE_UUID` picks it up.
if [ -f /etc/muid.data ]; then
    source /etc/muid.data
else
    echo "Warning: /etc/muid.data not found, using empty UUID" > /dev/tty3
    GP_PROBE_UUID=""
fi
export GP_PROBE_UUID

export GP_HOST_HW=true
export GP_HOST_DEVICE=v2
export GP_HOST_FIRMWARE=19.0.5

# Docker read-only mode configuration
# Default: false (--read-only flag NOT used)
# To enable: create /persist/jsdelivr-config/docker-readonly with content "true"
DOCKER_READONLY="false"
if [ -f /persist/jsdelivr-config/docker-readonly ]; then
    DOCKER_READONLY=$(cat /persist/jsdelivr-config/docker-readonly | tr -d '[:space:]')
fi
echo "Docker read-only mode: $DOCKER_READONLY" > /dev/tty3

# Function to initialize Docker repository with frozen image
# Only called if globalping-probe image doesn't exist
init_docker_repo() {
    echo "Initializing Docker repository - image not found" > /dev/tty3
    echo "Cleaning /var/lib/docker/*" > /dev/tty3

    # Stop Docker services
    /bin/systemctl stop docker
    /bin/systemctl stop containerd

    # Clean Docker storage
    rm -rf /var/lib/docker/*

    # Restart Docker services
    /bin/systemctl start containerd
    /bin/systemctl start docker

    # Wait for Docker to be ready (up to 60 seconds)
    wait_for_docker 60

    # Load frozen image
    echo "Loading globalping-probe image from frozen container" > /dev/tty3
    if [ -f /JSDELIVR_BASE_CONTAINER/globalping-probe.frozen ]; then
        if /usr/bin/docker load < /JSDELIVR_BASE_CONTAINER/globalping-probe.frozen > /dev/tty3; then
            echo "Image loaded successfully" > /dev/tty3
        else
            echo "ERROR: docker load failed for frozen container" > /dev/tty3
            echo "ERROR: docker load failed for frozen container" > /dev/console
            led_boot_failed
            while :; do sleep 60; done
        fi
    else
        echo "ERROR: Frozen container image not found at /JSDELIVR_BASE_CONTAINER/globalping-probe.frozen" > /dev/tty3
        echo "ERROR: Frozen container image not found" > /dev/console
        # Boot failed - set solid RED and halt; RAUC mark-good won't run, slot rolls back next reboot
        led_boot_failed
        while :; do sleep 60; done
    fi
}

echo "Starting JSDELIVR World" > /dev/tty3

# Set booting LED pattern: Slow blinking GREEN
led_booting

# Run first boot initialization
# Exit codes: 0 = success or already completed, 1 = error
if ! /usr/bin/jsdelivr-firstBoot.sh; then
    echo "ERROR: First boot initialization failed!" > /dev/tty3
    echo "ERROR: First boot initialization failed!" > /dev/console
    led_boot_failed
    # Don't continue with broken system - wait for user intervention
    echo "System halted due to first boot failure. Please check logs." > /dev/console
    while :; do sleep 60; done
fi

# firstBoot.sh may have just created /etc/muid.data; re-source so the rest of
# this script and the docker container both see the real UUID rather than the
# empty fallback we set at the top.
if [ -f /etc/muid.data ]; then
    source /etc/muid.data
    export GP_PROBE_UUID
fi

/usr/bin/jsdelivr-updateContainer.sh

/usr/bin/jsdelivr-maxPower.sh

/bin/systemctl stop containerd
/bin/systemctl stop docker

# Detect boot device (SD card = mmcblk0, eMMC = mmcblk2)
detect_boot_device

# Use partition labeled "docker" for Docker storage
# A/B layout: p3=rootfs-a, p4=rootfs-b, p5=persist, p6=docker, p7=docker_persist
# Using labels is more robust than hardcoded partition numbers
DOCKER_PARTITION="/dev/disk/by-label/docker"
# Fallback to partition number if label not found (for compatibility)
if [ ! -b "$DOCKER_PARTITION" ]; then
    DOCKER_PARTITION="/dev/${BOOT_DEVICE}p6"
fi

echo "Detected boot device: $BOOT_DEVICE" > /dev/tty3
echo "Using Docker storage partition: $DOCKER_PARTITION" > /dev/tty3

# Check if partition exists before mounting. Without persistent docker storage,
# the probe runs from rootfs/tmpfs and loses container state on every reboot —
# treat this as a boot failure rather than silently degrading.
if [ ! -b "$DOCKER_PARTITION" ]; then
    echo "ERROR: Docker storage partition $DOCKER_PARTITION does not exist!" > /dev/tty3
    echo "ERROR: Docker storage partition $DOCKER_PARTITION does not exist!" > /dev/console
    led_boot_failed
    while :; do sleep 60; done
fi
mkdir -p /var/lib/docker
if ! /bin/mount -o noatime "$DOCKER_PARTITION" /var/lib/docker; then
    echo "ERROR: Failed to mount $DOCKER_PARTITION" > /dev/tty3
    echo "ERROR: Failed to mount $DOCKER_PARTITION" > /dev/console
    led_boot_failed
    while :; do sleep 60; done
fi
echo "Successfully mounted $DOCKER_PARTITION to /var/lib/docker (noatime)" > /dev/tty3

# Mount partition for persistent container data (volumes)
# A/B layout: /persist is p5, docker_persist is p7
# Using labels is more robust than hardcoded partition numbers
DOCKER_PERSIST_PARTITION="/dev/disk/by-label/docker_persist"
# Fallback to partition number if label not found (for compatibility)
if [ ! -b "$DOCKER_PERSIST_PARTITION" ]; then
    DOCKER_PERSIST_PARTITION="/dev/${BOOT_DEVICE}p7"
fi
# /docker_persist holds container volumes (wireguard config, speedtest cache,
# the persistent UUID for read-only mode). Failure here means the probe runs
# without persistent state — treat as boot failure for parity with the
# /var/lib/docker mount above.
if [ ! -b "$DOCKER_PERSIST_PARTITION" ]; then
    echo "ERROR: Docker persist partition $DOCKER_PERSIST_PARTITION does not exist" > /dev/tty3
    echo "ERROR: Docker persist partition $DOCKER_PERSIST_PARTITION does not exist" > /dev/console
    led_boot_failed
    while :; do sleep 60; done
fi
mkdir -p /docker_persist
if ! /bin/mount -o noatime "$DOCKER_PERSIST_PARTITION" /docker_persist; then
    echo "ERROR: Failed to mount $DOCKER_PERSIST_PARTITION to /docker_persist" > /dev/tty3
    echo "ERROR: Failed to mount $DOCKER_PERSIST_PARTITION to /docker_persist" > /dev/console
    led_boot_failed
    while :; do sleep 60; done
fi
echo "Successfully mounted $DOCKER_PERSIST_PARTITION to /docker_persist" > /dev/tty3
# Safety fallback: create subdirectories if firstBoot.sh didn't create them.
# These are normally created by firstBoot.sh when the partition is first formatted.
[ -d /docker_persist/wireguard ] || mkdir -p /docker_persist/wireguard
[ -d /docker_persist/speedtest ] || mkdir -p /docker_persist/speedtest

# Always clean Docker runtime directory
rm -rf /var/run/docker/*

# Start Docker services
/bin/systemctl start containerd
/bin/systemctl start docker

# Wait for Docker to be ready (up to 60 seconds)
wait_for_docker 60

# Check if globalping-probe image exists.
# docker run below uses "globalping/globalping-probe" (no tag) which Docker
# resolves to ":latest". A grep on Repository:Tag would falsely succeed when
# only a versioned tag is present, then docker run fails. Use image inspect
# against the exact reference docker run will resolve.
echo "Checking for globalping-probe Docker image..." > /dev/tty3
if /usr/bin/docker image inspect globalping/globalping-probe:latest >/dev/null 2>&1; then
    echo "globalping-probe:latest image found - skipping initialization" > /dev/tty3
else
    echo "globalping-probe:latest image not found - initializing Docker repository" > /dev/tty3
    init_docker_repo
fi

# Load and start optional containers if container loader is available
if [ -f /usr/bin/jsdelivr-container-loader.sh ]; then
    echo "Loading optional containers..." > /dev/tty3
    source /usr/bin/jsdelivr-container-loader.sh

    # Load optional container images
    load_optional_containers

    # Start optional containers
    start_optional_containers
else
    echo "Optional container loader not found, skipping" > /dev/tty3
fi

/usr/bin/jsdelivr-grabDevLogs.sh &
/usr/bin/jsdelivr-mandatoryReboot.sh  &
/usr/bin/jsdelivr-systemMonitor.sh  &
/usr/bin/jsdelivr-systemWatchdog.sh &


sleep 3

/usr/bin/docker info  > /dev/tty3

echo "Running image/container...."  > /dev/tty3

/usr/bin/jsdelivr-normalPower.sh

# Create UUID file in persistent storage
touch /docker_persist/.globalping-probe-uuid

# Flag file to signal systemMonitor that boot is ready
BOOT_READY_FLAG="/tmp/.jsdelivr_boot_ready"

# Always use tmpfs for ephemeral directories to reduce flash writes
# These are applied regardless of read-only mode
TMPFS_OPTS="--tmpfs /tmp:rw,nosuid,nodev,noexec,size=64m --tmpfs /var/tmp:rw,nosuid,nodev,noexec,size=64m --tmpfs /run:rw,nosuid,nodev,noexec,size=32m --tmpfs /var/run:rw,nosuid,nodev,noexec,size=32m --tmpfs /var/log:rw,nosuid,nodev,noexec,size=32m"

# Build read-only options based on configuration
if [ "$DOCKER_READONLY" = "true" ]; then
    READONLY_OPTS="--read-only --tmpfs /etc/ssl/certs:rw,nosuid,nodev,noexec,size=8m -v /docker_persist/.globalping-probe-uuid:/.globalping-probe-uuid:rw"
    echo "Container will run in read-only mode" > /dev/tty3
else
    READONLY_OPTS=""
    echo "Container will run in read-write mode" > /dev/tty3
fi

# First container start attempt (before main loop)
# This ensures container is running before systemMonitor starts checking
echo "Starting container for the first time..." > /dev/tty3
docker rm -f globalping-probe 2>/dev/null
/usr/bin/docker run -d $TMPFS_OPTS $READONLY_OPTS --env GP_HOST_HW --env GP_HOST_DEVICE --env GP_HOST_FIRMWARE --env GP_PROBE_UUID --log-driver local --log-opt max-size=10m --network host --restart=always --name globalping-probe globalping/globalping-probe

# Signal that boot is ready - systemMonitor can now start checking
touch "$BOOT_READY_FLAG"
echo "Boot ready flag set, container started" > /dev/tty3

while [ 1 ]; do

    # Check globalping-probe (mandatory container)
    RUNNING=$(docker inspect --format='{{.State.Running}}' globalping-probe 2>/dev/null)

    if [ "$RUNNING" != "true" ]; then
        # Remove any existing stopped container to avoid "name already in use" error
        # This happens on reboots when container exists from previous boot but is stopped
        docker rm -f globalping-probe 2>/dev/null

        /usr/bin/docker run -d $TMPFS_OPTS $READONLY_OPTS --env GP_HOST_HW --env GP_HOST_DEVICE --env GP_HOST_FIRMWARE --env GP_PROBE_UUID --log-driver local --log-opt max-size=10m --network host --restart=always --name globalping-probe globalping/globalping-probe

    fi

    sleep 10

done
