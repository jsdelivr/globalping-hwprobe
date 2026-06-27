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

# Persist partition settings (rollback is now owned by rauc-boot-check.sh)
PERSIST_DIR="/persist/rauc"

# Ensure /persist is remounted ro on unexpected exit
cleanup_persist() {
    mount -o remount,ro /persist 2>/dev/null || true
}
trap cleanup_persist EXIT

log() {
    echo "[${LOG_TAG}] $*"
    $LOGGER -t "${LOG_TAG}" "$*" 2>/dev/null || true
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

    # Reset boot counter and persist good state.
    # mountpoint -q (not [ -d ${PERSIST_DIR} ]) — without a real mount check
    # writes can land in a rootfs overlay and be lost on reboot, leaving the
    # next rauc-boot-check still seeing the pre-validation counter and
    # eventually triggering an unwanted rollback.
    if [ -n "${BOOT_SLOT}" ] && [ "${BOOT_SLOT}" != "unknown" ] && mountpoint -q /persist; then
        if mount -o remount,rw /persist 2>/dev/null; then
            mkdir -p "${PERSIST_DIR}"
            echo "0" > "${PERSIST_DIR}/boot-count-${BOOT_SLOT}.tmp" && \
                mv "${PERSIST_DIR}/boot-count-${BOOT_SLOT}.tmp" "${PERSIST_DIR}/boot-count-${BOOT_SLOT}"
            echo "good" > "${PERSIST_DIR}/state-${BOOT_SLOT}.tmp" && \
                mv "${PERSIST_DIR}/state-${BOOT_SLOT}.tmp" "${PERSIST_DIR}/state-${BOOT_SLOT}"
            sync
            mount -o remount,ro /persist 2>/dev/null || \
                log "WARNING: failed to remount /persist ro after writing state"
            log "Boot counter reset and state set to good for slot ${BOOT_SLOT}"
        else
            log "ERROR: failed to remount /persist rw - validation state NOT persisted"
        fi
    else
        log "Warning: Cannot persist state - /persist not mounted or slot unknown"
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

    # Do NOT flip legacy_boot or reboot here. rauc-boot-check owns rollback decisions
    # (counter-based, with target-bootable safety check). Triggering rollback from
    # mark-good caused single transient docker failures to brick fresh-flashed
    # devices whose rootfs-b was empty.
    # We leave the boot counter alone so boot-check can increment it on next boot,
    # and do not mark the slot bad — transient validation failures should retry.
    log "Validation failed on slot ${BOOT_SLOT:-unknown} - leaving rollback to rauc-boot-check"
    exit 1
fi
