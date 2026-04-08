#!/bin/sh
# RAUC bootslot handler for NanoPi Zero2
# Returns the currently booted slot name (a or b)
#
# This script is called by RAUC when using bootloader=custom
# It must output only the bootname of the current slot

# Method 1: Check kernel cmdline for rauc.slot parameter
SLOT=$(grep -o 'rauc\.slot=[ab]' /proc/cmdline 2>/dev/null | cut -d= -f2)

if [ -n "$SLOT" ]; then
    echo "$SLOT"
    exit 0
fi

# Method 2: Check root partition label
ROOT_DEV=$(findmnt -n -o SOURCE / 2>/dev/null)
if [ -n "$ROOT_DEV" ]; then
    # Resolve to actual device if it's a symlink
    ROOT_DEV=$(readlink -f "$ROOT_DEV" 2>/dev/null || echo "$ROOT_DEV")

    # Check if we're on rootfs-a or rootfs-b
    if readlink -f /dev/disk/by-partlabel/rootfs-a 2>/dev/null | grep -q "$(basename $ROOT_DEV)"; then
        echo "a"
        exit 0
    elif readlink -f /dev/disk/by-partlabel/rootfs-b 2>/dev/null | grep -q "$(basename $ROOT_DEV)"; then
        echo "b"
        exit 0
    fi
fi

# Method 3: Check legacy_boot GPT flag
# The partition with legacy_boot set is the active boot partition
if command -v parted >/dev/null 2>&1; then
    # Find eMMC device
    DISK="/dev/mmcblk2"
    if [ -b "$DISK" ]; then
        # Check which partition has legacy_boot flag
        if parted -s "$DISK" print 2>/dev/null | grep -E "^\s*3\s" | grep -q "legacy_boot"; then
            echo "a"
            exit 0
        elif parted -s "$DISK" print 2>/dev/null | grep -E "^\s*4\s" | grep -q "legacy_boot"; then
            echo "b"
            exit 0
        fi
    fi
fi

# Default to slot a (initial installation)
echo "a"
exit 0
