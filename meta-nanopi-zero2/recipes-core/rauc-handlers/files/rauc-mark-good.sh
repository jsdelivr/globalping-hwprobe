#!/bin/sh
# RAUC Mark Good Script for NanoPi Zero2
#
# This script runs after the system has booted successfully and
# validates that critical services are running before marking
# the current slot as "good".
#
# In a rollback scenario:
# - If this script fails to mark the slot good
# - And the watchdog triggers or system reboots
# - The bootloader will boot the OTHER slot (previous known-good)
#
# Note: With legacy_boot GPT flag mechanism, "marking good" means
# we don't need to do anything - the current slot's flag is already set.
# This script validates the boot and logs status for monitoring.

RAUC_STATUS_DIR="/run/rauc"
BOOT_STATUS_FILE="${RAUC_STATUS_DIR}/boot-status"
GOOD_STATUS_FILE="${RAUC_STATUS_DIR}/good-status"
LOG_TAG="rauc-mark-good"
LOGGER="/usr/bin/logger"

# Configuration - services to validate before marking good
# These must be running for boot to be considered successful
REQUIRED_SERVICES="docker.service"

# Minimum uptime in seconds before considering boot successful
MIN_UPTIME=30

# Persist partition settings for rollback
PERSIST_DIR="/persist/rauc"
DISK="/dev/mmcblk2"
ROOTFS_A_PARTNUM=3
ROOTFS_B_PARTNUM=4

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
    echo "error: $*" >> "${GOOD_STATUS_FILE}"
    exit 1
}

log "Starting boot validation..."

# Check if boot-check has run
if [ ! -f "${BOOT_STATUS_FILE}" ]; then
    log "Warning: Boot status file not found - boot-check may not have run"
else
    . "${BOOT_STATUS_FILE}"
    log "Boot slot: ${BOOT_SLOT:-unknown}"
    log "Boot time: ${BOOT_TIME:-unknown}"
fi

# Check system uptime
UPTIME=$(cat /proc/uptime | cut -d. -f1)
log "Current uptime: ${UPTIME} seconds"

if [ "${UPTIME}" -lt "${MIN_UPTIME}" ]; then
    log "Waiting for minimum uptime (${MIN_UPTIME}s)..."
    WAIT_TIME=$((MIN_UPTIME - UPTIME))
    sleep ${WAIT_TIME}
    UPTIME=$(cat /proc/uptime | cut -d. -f1)
    log "Uptime after wait: ${UPTIME} seconds"
fi

# Validate required services
log "Validating required services..."
VALIDATION_PASSED=true

for service in ${REQUIRED_SERVICES}; do
    if systemctl is-active --quiet "${service}" 2>/dev/null; then
        log "Service ${service}: RUNNING"
    else
        log "Service ${service}: NOT RUNNING"
        VALIDATION_PASSED=false
    fi
done

# Check if Docker is responsive
if command -v docker >/dev/null 2>&1; then
    if docker info >/dev/null 2>&1; then
        log "Docker daemon: RESPONSIVE"
    else
        log "Docker daemon: NOT RESPONSIVE"
        VALIDATION_PASSED=false
    fi
else
    log "Docker command not found - skipping docker validation"
fi

# Check network connectivity (optional, don't fail on this)
if ping -c 1 -W 5 1.1.1.1 >/dev/null 2>&1; then
    log "Network connectivity: OK"
else
    log "Network connectivity: WARNING - no external connectivity"
    # Don't fail on network - system might be behind firewall
fi

# Validate rootfs integrity (basic check)
if [ -f /etc/os-release ]; then
    log "OS release file: EXISTS"
else
    log "OS release file: MISSING"
    VALIDATION_PASSED=false
fi

# Final validation result
if [ "${VALIDATION_PASSED}" = "true" ]; then
    log "Boot validation: PASSED"

    # Write good status file
    cat > "${GOOD_STATUS_FILE}" <<EOF
BOOT_SLOT=${BOOT_SLOT:-unknown}
VALIDATION_TIME=$(date -u +%s)
UPTIME=${UPTIME}
STATUS=good
EOF

    log "Slot ${BOOT_SLOT:-unknown} marked as good"

    # Reset boot counter and persist good state
    if [ -d "${PERSIST_DIR}" ] && [ -n "${BOOT_SLOT}" ] && [ "${BOOT_SLOT}" != "unknown" ]; then
        mount -o remount,rw /persist 2>/dev/null || true
        echo "0" > "${PERSIST_DIR}/boot-count-${BOOT_SLOT}.tmp" && \
            mv "${PERSIST_DIR}/boot-count-${BOOT_SLOT}.tmp" "${PERSIST_DIR}/boot-count-${BOOT_SLOT}"
        echo "good" > "${PERSIST_DIR}/state-${BOOT_SLOT}.tmp" && \
            mv "${PERSIST_DIR}/state-${BOOT_SLOT}.tmp" "${PERSIST_DIR}/state-${BOOT_SLOT}"
        sync
        mount -o remount,ro /persist 2>/dev/null || true
        log "Boot counter reset and state set to good for slot ${BOOT_SLOT}"
    else
        log "Warning: Cannot persist state - /persist/rauc not available or slot unknown"
    fi

    log "Boot validation completed successfully"
    exit 0
else
    log "Boot validation: FAILED"

    cat > "${GOOD_STATUS_FILE}" <<EOF
BOOT_SLOT=${BOOT_SLOT:-unknown}
VALIDATION_TIME=$(date -u +%s)
UPTIME=${UPTIME}
STATUS=failed
EOF

    # Determine rollback target
    if [ -n "${BOOT_SLOT}" ] && [ "${BOOT_SLOT}" != "unknown" ]; then
        if [ "${BOOT_SLOT}" = "a" ]; then
            OTHER_SLOT="b"
            CURRENT_PARTNUM=${ROOTFS_A_PARTNUM}
            OTHER_PARTNUM=${ROOTFS_B_PARTNUM}
        else
            OTHER_SLOT="a"
            CURRENT_PARTNUM=${ROOTFS_B_PARTNUM}
            OTHER_PARTNUM=${ROOTFS_A_PARTNUM}
        fi

        # Read other slot state
        OTHER_STATE="good"
        if [ -f "${PERSIST_DIR}/state-${OTHER_SLOT}" ]; then
            OTHER_STATE=$(cat "${PERSIST_DIR}/state-${OTHER_SLOT}" 2>/dev/null || echo "good")
        fi

        # Mark current slot as bad
        if [ -d "${PERSIST_DIR}" ]; then
            mount -o remount,rw /persist 2>/dev/null || true
            echo "bad" > "${PERSIST_DIR}/state-${BOOT_SLOT}.tmp" && \
                mv "${PERSIST_DIR}/state-${BOOT_SLOT}.tmp" "${PERSIST_DIR}/state-${BOOT_SLOT}"
            sync
        fi

        if [ "${OTHER_STATE}" != "bad" ]; then
            log "ROLLBACK: Validation failed, switching to slot ${OTHER_SLOT}"
            if [ -d "${PERSIST_DIR}" ]; then
                # Reset other slot's counter for fresh attempts
                echo "0" > "${PERSIST_DIR}/boot-count-${OTHER_SLOT}.tmp" && \
                    mv "${PERSIST_DIR}/boot-count-${OTHER_SLOT}.tmp" "${PERSIST_DIR}/boot-count-${OTHER_SLOT}"
                sync
                mount -o remount,ro /persist 2>/dev/null || true
            fi
            # Flip legacy_boot flag
            /usr/sbin/parted -s "${DISK}" set ${OTHER_PARTNUM} legacy_boot on
            /usr/sbin/parted -s "${DISK}" set ${CURRENT_PARTNUM} legacy_boot off
            sync
            set_rollback_leds
            log "Rebooting into slot ${OTHER_SLOT}..."
            reboot -f
            exit 0
        else
            log "CRITICAL: Both slots marked bad - staying on current slot ${BOOT_SLOT}"
            if [ -d "${PERSIST_DIR}" ]; then
                # Deadlock: clear current state to allow recovery
                echo "good" > "${PERSIST_DIR}/state-${BOOT_SLOT}.tmp" && \
                    mv "${PERSIST_DIR}/state-${BOOT_SLOT}.tmp" "${PERSIST_DIR}/state-${BOOT_SLOT}"
                echo "0" > "${PERSIST_DIR}/boot-count-${BOOT_SLOT}.tmp" && \
                    mv "${PERSIST_DIR}/boot-count-${BOOT_SLOT}.tmp" "${PERSIST_DIR}/boot-count-${BOOT_SLOT}"
                sync
                mount -o remount,ro /persist 2>/dev/null || true
            fi
            error "Boot validation failed - both slots bad, deadlock cleared"
        fi
    else
        error "Boot validation failed - slot unknown, cannot rollback"
    fi
fi
