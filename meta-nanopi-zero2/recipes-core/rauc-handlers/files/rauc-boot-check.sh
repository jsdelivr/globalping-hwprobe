#!/bin/sh
# RAUC Boot Slot Check Script for NanoPi Zero2
#
# This script runs early in boot to:
# 1. Detect which slot we booted from (rauc.slot= kernel parameter)
# 2. Verify the legacy_boot GPT flag is set correctly
# 3. Log boot slot information for debugging
# 4. Create status file for mark-good service
#
# This is part of the A/B update validation flow.

RAUC_STATUS_DIR="/run/rauc"
BOOT_STATUS_FILE="${RAUC_STATUS_DIR}/boot-status"
LOG_TAG="rauc-boot-check"
LOGGER="/usr/bin/logger"
GREP="/bin/grep"

# Ensure /persist is remounted ro on unexpected exit
cleanup_persist() {
    mount -o remount,ro /persist 2>/dev/null || true
}
trap cleanup_persist EXIT

set_rollback_leds() {
    # Both LEDs solid to signal rollback in progress
    SYS_LED="/sys/class/leds/sys_led/brightness"
    USER_LED="/sys/class/leds/user_led/brightness"
    if [ -f "$SYS_LED" ]; then
        echo 1 > "$SYS_LED" 2>/dev/null || true
    fi
    if [ -f "$USER_LED" ]; then
        echo 1 > "$USER_LED" 2>/dev/null || true
    fi
}

log() {
    echo "[${LOG_TAG}] $*"
    $LOGGER -t "${LOG_TAG}" "$*" 2>/dev/null || true
}

error() {
    log "ERROR: $*"
    echo "error: $*" > "${BOOT_STATUS_FILE}"
    exit 1
}

# Ensure status directory exists
mkdir -p "${RAUC_STATUS_DIR}"

log "Starting boot slot verification..."

# Read rauc.slot parameter from kernel command line
RAUC_SLOT=$($GREP -o 'rauc\.slot=[ab]' /proc/cmdline | cut -d= -f2)

if [ -z "${RAUC_SLOT}" ]; then
    log "Warning: rauc.slot parameter not found in kernel cmdline"
    log "Assuming slot 'a' (initial installation)"
    RAUC_SLOT="a"
fi

log "Detected boot slot: ${RAUC_SLOT}"

# =============================================================================
# Boot counter and auto-rollback logic
# =============================================================================
MAX_BOOT_ATTEMPTS=3
PERSIST_DIR="/persist/rauc"

# Ensure persist directory exists for boot counter
if mountpoint -q /persist 2>/dev/null; then
    if [ ! -d "${PERSIST_DIR}" ]; then
        mount -o remount,rw /persist 2>/dev/null || true
        mkdir -p "${PERSIST_DIR}"
        mount -o remount,ro /persist 2>/dev/null || true
    fi
fi
DISK="/dev/mmcblk2"
ROOTFS_A_PARTNUM=3
ROOTFS_B_PARTNUM=4

# Determine the other slot
if [ "${RAUC_SLOT}" = "a" ]; then
    OTHER_SLOT="b"
    CURRENT_PARTNUM=${ROOTFS_A_PARTNUM}
    OTHER_PARTNUM=${ROOTFS_B_PARTNUM}
else
    OTHER_SLOT="a"
    CURRENT_PARTNUM=${ROOTFS_B_PARTNUM}
    OTHER_PARTNUM=${ROOTFS_A_PARTNUM}
fi

COUNTER_FILE="${PERSIST_DIR}/boot-count-${RAUC_SLOT}"
STATE_FILE="${PERSIST_DIR}/state-${RAUC_SLOT}"
OTHER_STATE_FILE="${PERSIST_DIR}/state-${OTHER_SLOT}"
OTHER_COUNTER_FILE="${PERSIST_DIR}/boot-count-${OTHER_SLOT}"

# Read boot counter (default 0 if missing or /persist unavailable)
BOOT_COUNT=0
if [ -f "${COUNTER_FILE}" ]; then
    BOOT_COUNT=$(cat "${COUNTER_FILE}" 2>/dev/null || echo "0")
    # Sanitize: ensure it's a number
    case "${BOOT_COUNT}" in
        ''|*[!0-9]*) BOOT_COUNT=0 ;;
    esac
fi
log "Boot counter for slot ${RAUC_SLOT}: ${BOOT_COUNT} (max ${MAX_BOOT_ATTEMPTS})"

# Read other slot state
OTHER_STATE="good"
if [ -f "${OTHER_STATE_FILE}" ]; then
    OTHER_STATE=$(cat "${OTHER_STATE_FILE}" 2>/dev/null || echo "good")
fi

if [ "${BOOT_COUNT}" -ge "${MAX_BOOT_ATTEMPTS}" ]; then
    log "Boot counter reached threshold (${BOOT_COUNT} >= ${MAX_BOOT_ATTEMPTS})"

    # Safety: refuse to roll back into an unbootable slot. Mount target partition
    # read-only and check for /boot/extlinux/extlinux.conf. If missing (e.g. fresh
    # flash where rootfs-b was never populated), clear counter/state and keep
    # running on the current slot instead of bricking the device.
    OTHER_DEV="${DISK}p${OTHER_PARTNUM}"
    TARGET_MOUNT="/run/rauc-target-check"
    TARGET_BOOTABLE=false
    mkdir -p "${TARGET_MOUNT}"
    if mount -o ro "${OTHER_DEV}" "${TARGET_MOUNT}" 2>/dev/null; then
        if [ -f "${TARGET_MOUNT}/boot/extlinux/extlinux.conf" ] && [ -f "${TARGET_MOUNT}/boot/Image" ]; then
            TARGET_BOOTABLE=true
        fi
        umount "${TARGET_MOUNT}" 2>/dev/null || true
    fi
    rmdir "${TARGET_MOUNT}" 2>/dev/null || true

    if [ "${TARGET_BOOTABLE}" != "true" ]; then
        log "ABORT ROLLBACK: slot ${OTHER_SLOT} (${OTHER_DEV}) missing /boot/extlinux/extlinux.conf or /boot/Image"
        log "Clearing counter and forcing state=good on slot ${RAUC_SLOT} to prevent brick"
        if [ -d "${PERSIST_DIR}" ]; then
            mount -o remount,rw /persist 2>/dev/null || true
            echo "0" > "${COUNTER_FILE}.tmp" && mv "${COUNTER_FILE}.tmp" "${COUNTER_FILE}"
            echo "good" > "${STATE_FILE}.tmp" && mv "${STATE_FILE}.tmp" "${STATE_FILE}"
            sync
            mount -o remount,ro /persist 2>/dev/null || true
        fi
        NEW_COUNT=0
    elif [ "${OTHER_STATE}" != "bad" ]; then
        log "ROLLBACK: Switching to slot ${OTHER_SLOT}"
        # Mark current slot as bad, reset other slot's counter
        if [ -d "${PERSIST_DIR}" ]; then
            mount -o remount,rw /persist 2>/dev/null || true
            echo "bad" > "${STATE_FILE}.tmp" && mv "${STATE_FILE}.tmp" "${STATE_FILE}"
            echo "0" > "${OTHER_COUNTER_FILE}.tmp" && mv "${OTHER_COUNTER_FILE}.tmp" "${OTHER_COUNTER_FILE}"
            sync
            mount -o remount,ro /persist 2>/dev/null || true
        fi
        # Flip legacy_boot flag to other slot
        /usr/sbin/parted -s "${DISK}" set ${OTHER_PARTNUM} legacy_boot on
        /usr/sbin/parted -s "${DISK}" set ${CURRENT_PARTNUM} legacy_boot off
        sync
        set_rollback_leds
        log "Rebooting into slot ${OTHER_SLOT}..."
        reboot -f
        exit 0
    else
        log "DEADLOCK: Both slots in bad state - breaking deadlock"
        NEW_COUNT=0
        # Both slots bad: clear counters, mark current as good, continue booting
        if [ -d "${PERSIST_DIR}" ]; then
            mount -o remount,rw /persist 2>/dev/null || true
            echo "0" > "${COUNTER_FILE}.tmp" && mv "${COUNTER_FILE}.tmp" "${COUNTER_FILE}"
            echo "0" > "${OTHER_COUNTER_FILE}.tmp" && mv "${OTHER_COUNTER_FILE}.tmp" "${OTHER_COUNTER_FILE}"
            echo "good" > "${STATE_FILE}.tmp" && mv "${STATE_FILE}.tmp" "${STATE_FILE}"
            sync
            mount -o remount,ro /persist 2>/dev/null || true
        fi
        log "Deadlock broken - continuing boot on slot ${RAUC_SLOT}"
    fi
else
    # Increment boot counter
    NEW_COUNT=$((BOOT_COUNT + 1))
    if [ -d "${PERSIST_DIR}" ]; then
        mount -o remount,rw /persist 2>/dev/null || true
        echo "${NEW_COUNT}" > "${COUNTER_FILE}.tmp" && mv "${COUNTER_FILE}.tmp" "${COUNTER_FILE}"
        sync
        mount -o remount,ro /persist 2>/dev/null || true
        log "Boot counter incremented: ${BOOT_COUNT} -> ${NEW_COUNT}"
    else
        log "Warning: /persist/rauc not available, boot counter not updated"
    fi
fi

# Determine expected partition based on slot
if [ "${RAUC_SLOT}" = "a" ]; then
    EXPECTED_PARTLABEL="rootfs-a"
elif [ "${RAUC_SLOT}" = "b" ]; then
    EXPECTED_PARTLABEL="rootfs-b"
else
    error "Invalid RAUC slot: ${RAUC_SLOT}"
fi

# Verify we're actually on the expected rootfs
# Check /proc/mounts for root device
ROOT_DEV=$($GREP ' / ' /proc/mounts | head -n 1 | cut -d' ' -f1)
log "Root device: ${ROOT_DEV}"

# Verify by checking if the expected PARTLABEL device exists and matches root
PARTLABEL_DEV="/dev/disk/by-partlabel/${EXPECTED_PARTLABEL}"
if [ -L "${PARTLABEL_DEV}" ]; then
    PARTLABEL_RESOLVED=$(readlink -f "${PARTLABEL_DEV}")
    ROOT_RESOLVED=$(readlink -f "${ROOT_DEV}" 2>/dev/null || echo "${ROOT_DEV}")

    if [ "${PARTLABEL_RESOLVED}" = "${ROOT_RESOLVED}" ]; then
        log "Root device verification: OK (${ROOT_DEV} = ${EXPECTED_PARTLABEL})"
    else
        log "Warning: Root device mismatch - actual: ${ROOT_RESOLVED}, expected: ${PARTLABEL_RESOLVED}"
    fi
else
    log "Warning: Partition label ${EXPECTED_PARTLABEL} not found"
fi

# Find boot disk device
BOOT_DISK=""
if echo "${ROOT_DEV}" | $GREP -q "mmcblk"; then
    BOOT_DISK=$(echo "${ROOT_DEV}" | sed 's/p[0-9]*$//')
elif echo "${ROOT_DEV}" | $GREP -q "sd[a-z]"; then
    BOOT_DISK=$(echo "${ROOT_DEV}" | sed 's/[0-9]*$//')
fi

if [ -n "${BOOT_DISK}" ] && [ -b "${BOOT_DISK}" ]; then
    log "Boot disk: ${BOOT_DISK}"

    # Check legacy_boot flag status (if parted is available)
    if command -v parted >/dev/null 2>&1; then
        log "Checking legacy_boot GPT flags..."

        # Get partition flags
        PART3_FLAGS=$(parted -s "${BOOT_DISK}" print | $GREP "^\s*3\s" | sed 's/.*legacy_boot.*/legacy_boot/' || echo "none")
        PART4_FLAGS=$(parted -s "${BOOT_DISK}" print | $GREP "^\s*4\s" | sed 's/.*legacy_boot.*/legacy_boot/' || echo "none")

        log "Partition 3 (rootfs-a) legacy_boot: ${PART3_FLAGS}"
        log "Partition 4 (rootfs-b) legacy_boot: ${PART4_FLAGS}"

        # Verify current slot has legacy_boot flag
        if [ "${RAUC_SLOT}" = "a" ] && echo "${PART3_FLAGS}" | $GREP -q "legacy_boot"; then
            log "legacy_boot flag verification: OK"
        elif [ "${RAUC_SLOT}" = "b" ] && echo "${PART4_FLAGS}" | $GREP -q "legacy_boot"; then
            log "legacy_boot flag verification: OK"
        else
            log "Warning: legacy_boot flag not set on current slot partition"
        fi
    else
        log "parted not available - skipping flag verification"
    fi
else
    log "Warning: Could not determine boot disk"
fi

# Check RAUC status if available
if command -v rauc >/dev/null 2>&1; then
    log "Querying RAUC status..."
    rauc status --output-format=readable 2>/dev/null || log "RAUC status query failed"
fi

# Write boot status file for mark-good service
cat > "${BOOT_STATUS_FILE}" <<EOF
BOOT_SLOT=${RAUC_SLOT}
BOOT_TIME=$(date -u +%s)
ROOT_DEV=${ROOT_DEV}
BOOT_DISK=${BOOT_DISK}
BOOT_COUNT=${NEW_COUNT:-${BOOT_COUNT}}
STATUS=booted
EOF

log "Boot status file created: ${BOOT_STATUS_FILE}"
log "Boot slot check completed successfully for slot ${RAUC_SLOT}"

exit 0
