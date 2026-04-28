#!/bin/bash
# jsdelivr-utils.sh - Shared utility functions for jsdelivr scripts
# Copyright (C) 2025

# =============================================================================
# LED Control Constants
# =============================================================================
LED_RED="/sys/class/leds/sys_led"
LED_GREEN="/sys/class/leds/user_led"

# =============================================================================
# LED Control Functions
# =============================================================================
# LED Patterns for Production Images:
#   led_booting            - Slow blinking GREEN (1s on/1s off)
#   led_container_starting - Fast blinking GREEN (100ms on/100ms off)
#   led_container_stable   - Solid GREEN
#   led_boot_failed        - Solid RED
#   led_container_failed   - Fast blinking RED (500ms on/500ms off)
#
# Usage:
#   source /usr/bin/jsdelivr-utils.sh
#   led_booting
#   # ... do boot stuff ...
#   led_container_stable

# Internal helper: write to an LED sysfs attribute if it exists.
# Silently no-ops on hardware/dev environments where the LED paths are absent
# (e.g. running scripts inside the SDK or on a board with different LED bindings),
# so callers don't blow up and abort boot just because a status indicator is missing.
_led_write() {
    local path="$1"
    local value="$2"
    [ -w "$path" ] && echo "$value" > "$path" 2>/dev/null || true
}

# Turn off both LEDs
led_off() {
    _led_write "${LED_RED}/trigger" "none"
    _led_write "${LED_RED}/brightness" 0
    _led_write "${LED_GREEN}/trigger" "none"
    _led_write "${LED_GREEN}/brightness" 0
}

# Booting: Slow blinking GREEN (1s on/1s off)
led_booting() {
    _led_write "${LED_RED}/trigger" "none"
    _led_write "${LED_RED}/brightness" 0
    _led_write "${LED_GREEN}/trigger" "timer"
    sleep 0.2
    _led_write "${LED_GREEN}/delay_on" 1000
    _led_write "${LED_GREEN}/delay_off" 1000
}

# Container starting: Fast blinking GREEN (100ms on/100ms off)
led_container_starting() {
    _led_write "${LED_RED}/trigger" "none"
    _led_write "${LED_RED}/brightness" 0
    _led_write "${LED_GREEN}/trigger" "timer"
    sleep 0.2
    _led_write "${LED_GREEN}/delay_on" 100
    _led_write "${LED_GREEN}/delay_off" 100
}

# Container stable: Solid GREEN
led_container_stable() {
    _led_write "${LED_RED}/trigger" "none"
    _led_write "${LED_RED}/brightness" 0
    _led_write "${LED_GREEN}/trigger" "none"
    _led_write "${LED_GREEN}/brightness" 1
}

# Boot failed: Solid RED
led_boot_failed() {
    _led_write "${LED_GREEN}/trigger" "none"
    _led_write "${LED_GREEN}/brightness" 0
    _led_write "${LED_RED}/trigger" "none"
    _led_write "${LED_RED}/brightness" 1
}

# Container failed: Fast blinking RED (500ms on/500ms off)
led_container_failed() {
    _led_write "${LED_GREEN}/trigger" "none"
    _led_write "${LED_GREEN}/brightness" 0
    _led_write "${LED_RED}/trigger" "timer"
    sleep 0.2
    _led_write "${LED_RED}/delay_on" 500
    _led_write "${LED_RED}/delay_off" 500
}

# =============================================================================
# Docker Readiness Functions
# =============================================================================
#
# wait_for_docker()
#
# Waits for Docker daemon to be fully ready by polling `docker info`.
# Times out after specified seconds (default 60).
#
# Usage:
#   source /usr/bin/jsdelivr-utils.sh
#   wait_for_docker 30   # Wait up to 30 seconds
#   wait_for_docker      # Wait up to 60 seconds (default)
#
wait_for_docker() {
    local timeout=${1:-60}
    local count=0

    echo "Waiting for Docker daemon to be ready (timeout: ${timeout}s)..." >&2

    while [ $count -lt $timeout ]; do
        if docker info >/dev/null 2>&1; then
            echo "Docker is ready after ${count} seconds" >&2
            return 0
        fi
        sleep 1
        count=$((count + 1))
    done

    echo "WARNING: Docker not ready after ${timeout} seconds" >&2
    return 1
}

# =============================================================================
# Boot Device Detection
# =============================================================================
#
# detect_boot_device()
#
# Detects whether the system booted from SD card (mmcblk0) or eMMC (mmcblk2)
# by checking kernel command line and mounted partitions.
#
# Sets global variable: BOOT_DEVICE (either "mmcblk0" or "mmcblk2")
#
# Usage:
#   source /usr/bin/jsdelivr-utils.sh
#   detect_boot_device
#   echo "Booted from: $BOOT_DEVICE"
#
detect_boot_device() {
    BOOT_DEVICE=""

    # Check kernel command line for explicit root device
    if grep -q "root=/dev/mmcblk0" /proc/cmdline; then
        BOOT_DEVICE="mmcblk0"
    elif grep -q "root=/dev/mmcblk2" /proc/cmdline; then
        BOOT_DEVICE="mmcblk2"
    elif grep -qE "PARTLABEL=rootfs-[ab]" /proc/cmdline; then
        # RAUC A/B layout uses rootfs-a or rootfs-b partition labels
        # Determine device from the root mount
        ROOT_DEV=$(findmnt -n -o SOURCE / 2>/dev/null)
        if echo "$ROOT_DEV" | grep -q "mmcblk0"; then
            BOOT_DEVICE="mmcblk0"
        elif echo "$ROOT_DEV" | grep -q "mmcblk2"; then
            BOOT_DEVICE="mmcblk2"
        fi
    elif grep -q "LABEL=rootfs" /proc/cmdline || grep -q "PARTLABEL=rootfs" /proc/cmdline || grep -q "/dev/root" /proc/cmdline; then
        # If using LABEL/PARTLABEL or /dev/root, check which mmcblk device has mounted partitions
        if mount | grep -q "^/dev/mmcblk0"; then
            BOOT_DEVICE="mmcblk0"
        elif mount | grep -q "^/dev/mmcblk2"; then
            BOOT_DEVICE="mmcblk2"
        else
            # Fallback: check which device exists and has partitions
            if [ -b /dev/mmcblk0p3 ]; then
                BOOT_DEVICE="mmcblk0"
            elif [ -b /dev/mmcblk2p3 ]; then
                BOOT_DEVICE="mmcblk2"
            fi
        fi
    fi

    # Fallback to SD card if detection failed
    if [ -z "$BOOT_DEVICE" ]; then
        BOOT_DEVICE="mmcblk0"
        echo "Warning: Could not detect boot device, defaulting to SD card (mmcblk0)" >&2
    fi

    # Export so it's available to calling scripts
    export BOOT_DEVICE
}
