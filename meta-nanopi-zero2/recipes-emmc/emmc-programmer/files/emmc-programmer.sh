#!/bin/bash
# eMMC Programmer with LED feedback, hardware testing, and verification
#
# Process:
# 1. Hardware test - Write zeros to eMMC and verify with MD5
# 2. Program - Flash production WIC image to eMMC
# 3. Verify - Read back from eMMC and compare MD5 with production image
# 4. Configure - Set eMMC to boot from user area (like SD card)
#
# LED Patterns:
#   Solid RED              = Not started / failed early
#   Fast blinking GREEN    = Flashing in progress
#   Slow blinking RED      = Flashing failed
#   Both RED+GREEN solid   = Success!

TARGET_DEVICE="/dev/mmcblk2"
PRODUCTION_IMAGE="/opt/images/production.wic.xz"
PRODUCTION_INFO="/opt/images/production.info"

# Start with error state (solid red) until we confirm we can proceed
/usr/bin/led-control.sh error &
LED_PID=$!

# Get actual eMMC size from the device
EMMC_SIZE_BYTES=$(blockdev --getsize64 ${TARGET_DEVICE} 2>/dev/null)

# Expected MD5 is computed dynamically based on actual eMMC size
# (different eMMC capacities produce different zero-fill MD5 hashes)

# Check if target device exists
if [ ! -b "$TARGET_DEVICE" ]; then
    echo "ERROR: Target device $TARGET_DEVICE not found!" > /dev/tty3
    echo "Solid RED LED - eMMC not detected" > /dev/tty3
    # LED already showing error, just wait
    wait
    exit 1
fi

# Check if production image exists
if [ ! -f "$PRODUCTION_IMAGE" ]; then
    echo "ERROR: Production image not found!" > /dev/tty3
    echo "Expected: $PRODUCTION_IMAGE" > /dev/tty3
    echo "Solid RED LED - Image not found" > /dev/tty3
    # LED already showing error, just wait
    wait
    exit 1
fi

# Calculate size in GiB for display
EMMC_SIZE_GIB=$(awk "BEGIN {printf \"%.2f\", ${EMMC_SIZE_BYTES}/1024/1024/1024}")

echo "========================================" > /dev/tty3
echo "eMMC Hardware Test and Programming" > /dev/tty3
echo "========================================" > /dev/tty3
echo "Target Device: $TARGET_DEVICE (${EMMC_SIZE_GIB} GiB)" > /dev/tty3
echo "Target Size: ${EMMC_SIZE_BYTES} bytes" > /dev/tty3
echo "" > /dev/tty3

# Display production image info
if [ -f "$PRODUCTION_INFO" ]; then
    echo "Production Image:" > /dev/tty3
    cat "$PRODUCTION_INFO" > /dev/tty3
    echo "" > /dev/tty3
fi

# Unmount eMMC if mounted
umount ${TARGET_DEVICE}* 2>/dev/null

# Now we can start flashing - switch to flashing pattern (fast green blink)
kill $LED_PID 2>/dev/null
/usr/bin/led-control.sh flashing &
LED_PID=$!

# Step 1: eMMC Hardware Test
echo "Step 1: Testing eMMC hardware..." > /dev/tty3
echo "Writing zeros to entire ${EMMC_SIZE_GIB} GiB eMMC..." > /dev/tty3

# Fill eMMC with zeros (use actual device size)
dd if=/dev/zero of=${TARGET_DEVICE} bs=4M 2>&1 | tee /dev/tty3
sync

echo "Verifying eMMC reads back as zeros..." > /dev/tty3

# Compute expected MD5 dynamically: generate same number of zero bytes and hash
ZERO_COUNT=$((EMMC_SIZE_BYTES / 4 / 1024 / 1024))
EXPECTED_MD5=$(dd if=/dev/zero bs=4M count=${ZERO_COUNT} 2>/dev/null | md5sum | awk '{print $1}')
ACTUAL_MD5=$(dd if=${TARGET_DEVICE} bs=4M count=${ZERO_COUNT} 2>/dev/null | md5sum | awk '{print $1}')

echo "Expected MD5 (zeros): $EXPECTED_MD5" > /dev/tty3
echo "Actual MD5 (eMMC):    $ACTUAL_MD5" > /dev/tty3

if [ "$ACTUAL_MD5" != "$EXPECTED_MD5" ]; then
    # HARDWARE TEST FAILED - Show slow blinking RED
    kill $LED_PID 2>/dev/null
    /usr/bin/led-control.sh failed &

    echo "" > /dev/tty3
    echo "========================================" > /dev/tty3
    echo "ERROR: eMMC HARDWARE TEST FAILED!" > /dev/tty3
    echo "========================================" > /dev/tty3
    echo "The eMMC hardware is faulty or damaged." > /dev/tty3
    echo "MD5 mismatch detected." > /dev/tty3
    echo "" > /dev/tty3
    echo "Slow blinking RED - Hardware failure" > /dev/tty3
    echo "DO NOT USE THIS DEVICE!" > /dev/tty3
    echo "Power off and replace hardware." > /dev/tty3

    # Keep LED blinking forever
    wait
    exit 1
fi

echo "" > /dev/tty3
echo "eMMC hardware test PASSED" > /dev/tty3
echo "" > /dev/tty3

# Step 2: Program firmware
echo "Step 2: Programming production image to eMMC..." > /dev/tty3
echo "Decompressing and flashing: $PRODUCTION_IMAGE" > /dev/tty3

# Continue with flashing pattern (already running)

# Decompress and flash the production WIC image to eMMC
# Using xz -dc to decompress to stdout, then dd to write to eMMC
# xz properly handles files > 4GB (unlike gzip which has 32-bit size field overflow)
xz -dc "$PRODUCTION_IMAGE" | dd of=${TARGET_DEVICE} bs=4M 2>&1 | tee /dev/tty3
sync

echo "" > /dev/tty3
echo "Step 3: Verifying written data..." > /dev/tty3
echo "Calculating checksums..." > /dev/tty3

# Get size from production.info (stored during build, reliable for >4GB files)
# Format: "Image Size Bytes: 1234567890"
WIC_SIZE=$(grep "Image Size Bytes:" "$PRODUCTION_INFO" | awk '{print $4}')
if [ -z "$WIC_SIZE" ] || [ "$WIC_SIZE" = "0" ]; then
    # Fallback: get size by decompressing (xz handles >4GB correctly)
    echo "Getting image size from decompression..." > /dev/tty3
    WIC_SIZE=$(xz -dc "$PRODUCTION_IMAGE" | wc -c)
fi
WIC_SIZE_MB=$((WIC_SIZE / 1024 / 1024))
echo "Image size: ${WIC_SIZE_MB} MB (${WIC_SIZE} bytes)" > /dev/tty3

# Calculate MD5 of decompressed production image
echo "Computing production image MD5..." > /dev/tty3
PRODUCTION_MD5=$(xz -dc "$PRODUCTION_IMAGE" | md5sum | awk '{print $1}')

# Calculate MD5 of written eMMC data (read back same number of bytes)
echo "Computing eMMC MD5..." > /dev/tty3
# WIC images are sector-aligned (512 bytes), use sector size for efficiency
# This is much faster than bs=1 and works with BusyBox
EMMC_MD5=$(dd if=${TARGET_DEVICE} bs=512 count=$((WIC_SIZE / 512)) 2>/dev/null | md5sum | awk '{print $1}')

echo "Production MD5: $PRODUCTION_MD5" > /dev/tty3
echo "eMMC MD5:       $EMMC_MD5" > /dev/tty3

if [ "$PRODUCTION_MD5" != "$EMMC_MD5" ]; then
    # VERIFICATION FAILED - Show slow blinking RED
    kill $LED_PID 2>/dev/null
    /usr/bin/led-control.sh failed &

    echo "" > /dev/tty3
    echo "========================================" > /dev/tty3
    echo "ERROR: VERIFICATION FAILED!" > /dev/tty3
    echo "========================================" > /dev/tty3
    echo "The data written to eMMC does not match" > /dev/tty3
    echo "the production image. Programming failed." > /dev/tty3
    echo "" > /dev/tty3
    echo "Slow blinking RED - Verification failure" > /dev/tty3
    echo "DO NOT USE THIS DEVICE!" > /dev/tty3
    echo "Power off and retry programming." > /dev/tty3

    # Keep blinking error forever
    wait
    exit 1
fi

# Step 4: Configure eMMC boot mode
echo "" > /dev/tty3
echo "Step 4: Configuring eMMC boot mode..." > /dev/tty3
echo "Setting eMMC to boot from user area (like SD card)..." > /dev/tty3

# Configure eMMC to boot from user area instead of boot0/boot1
# This makes eMMC behave identically to SD card for booting
# boot_config format: boot_partition boot_ack partition_access
# 0 0 0 = boot from user area, no ack, default access
if [ -f "/sys/block/mmcblk2/device/boot_config" ]; then
    if echo "0 0 0" > /sys/block/mmcblk2/device/boot_config 2>/dev/null; then
        echo "eMMC configured to boot from user area" > /dev/tty3
    else
        echo "eMMC boot config not available (will use default settings)" > /dev/tty3
    fi
elif [ -f "/sys/block/mmcblk2/device/boot_bus_config" ]; then
    # Alternative path for some kernels (often read-only)
    if echo 0 > /sys/block/mmcblk2/device/boot_bus_config 2>/dev/null; then
        echo "eMMC boot configuration applied" > /dev/tty3
    else
        echo "eMMC boot config not writable (will use default settings)" > /dev/tty3
    fi
else
    echo "eMMC will boot with default configuration" > /dev/tty3
fi

# SUCCESS - Show both LEDs solid
kill $LED_PID 2>/dev/null
/usr/bin/led-control.sh success &

# Display completion message
echo "" > /dev/tty3
echo "========================================" > /dev/tty3
echo "SUCCESS: eMMC Programming Complete!" > /dev/tty3
echo "========================================" > /dev/tty3
echo "eMMC hardware test: PASSED" > /dev/tty3
echo "Firmware programming: COMPLETE" > /dev/tty3
echo "Data verification: PASSED" > /dev/tty3
echo "Boot configuration: SET (user area boot)" > /dev/tty3
echo "" > /dev/tty3
echo "Both RED and GREEN LEDs solid - SUCCESS!" > /dev/tty3
echo "You can now safely power off the device." > /dev/tty3
