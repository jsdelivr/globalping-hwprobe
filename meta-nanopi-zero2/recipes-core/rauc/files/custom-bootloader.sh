#!/bin/sh
# RAUC Custom Bootloader Backend for NanoPi Zero2
# Uses GPT legacy_boot flag for A/B boot selection
#
# RAUC calls this script with command-line arguments:
#   get-primary           - return current primary slot on stdout (a or b)
#   set-primary <slot>    - set primary boot slot (a or b)
#   get-state <slot>      - return slot state on stdout (good/bad)
#   set-state <slot> <state> - set slot state (good/bad)
#
# IMPORTANT: Arguments are passed as command-line args ($1, $2, $3),
# NOT as environment variables like RAUC_SLOT_BOOTNAME!

# Use full paths for commands (RAUC may not have full PATH)
PARTED="/usr/sbin/parted"
GREP="/bin/grep"
LOGGER="/usr/bin/logger"

# Derive boot disk from /proc/mounts so RAUC slot flips target the disk we
# actually booted from (mmcblk2 eMMC in production; mmcblk0 if the same image
# is dd'd to an SD card for testing). Falls back to mmcblk2 on detection
# failure to preserve the previous behavior.
ROOT_DEV_EARLY=$($GREP ' / ' /proc/mounts 2>/dev/null | head -n 1 | cut -d' ' -f1)
case "$ROOT_DEV_EARLY" in
    /dev/mmcblk0p*) DISK="/dev/mmcblk0" ;;
    /dev/mmcblk2p*) DISK="/dev/mmcblk2" ;;
    *)              DISK="/dev/mmcblk2" ;;
esac
ROOTFS_A_PARTNUM=3
ROOTFS_B_PARTNUM=4
PERSIST_DIR="/persist/rauc"

# Pre-install opens /persist rw and post-install closes it; don't fight that.
PERSIST_OPENED_BY_US=0
cleanup_persist() {
    [ "$PERSIST_OPENED_BY_US" -eq 1 ] && mount -o remount,ro /persist 2>/dev/null || true
}
trap cleanup_persist EXIT

persist_is_rw() {
    awk '$2 == "/persist" {print $4}' /proc/mounts 2>/dev/null | grep -qE '^rw($|,)'
}

log() {
    echo "[rauc-bootloader] $*" >&2
    $LOGGER -t rauc-bootloader "$*" 2>/dev/null || true
}

get_primary() {
    PARTED_OUT=$($PARTED -s "$DISK" print 2>/dev/null)
    if echo "$PARTED_OUT" | $GREP -E "^\s*${ROOTFS_A_PARTNUM}\s" | $GREP -q "legacy_boot"; then
        echo "a"
    elif echo "$PARTED_OUT" | $GREP -E "^\s*${ROOTFS_B_PARTNUM}\s" | $GREP -q "legacy_boot"; then
        echo "b"
    else
        # Default to current slot from kernel cmdline, or 'a' if not found
        SLOT=$($GREP -o 'rauc\.slot=[ab]' /proc/cmdline 2>/dev/null | cut -d= -f2)
        echo "${SLOT:-a}"
    fi
}

set_primary() {
    # $1 = slot (a or b) - passed as command-line argument by RAUC
    SLOT="$1"
    log "Setting primary slot to: $SLOT"

    if [ "$SLOT" = "a" ]; then
        if ! $PARTED -s "$DISK" set $ROOTFS_A_PARTNUM legacy_boot on; then
            log "ERROR: Failed to set legacy_boot on partition $ROOTFS_A_PARTNUM"
            exit 1
        fi
        if ! $PARTED -s "$DISK" set $ROOTFS_B_PARTNUM legacy_boot off; then
            log "ERROR: Failed to clear legacy_boot on partition $ROOTFS_B_PARTNUM"
            exit 1
        fi
    elif [ "$SLOT" = "b" ]; then
        if ! $PARTED -s "$DISK" set $ROOTFS_B_PARTNUM legacy_boot on; then
            log "ERROR: Failed to set legacy_boot on partition $ROOTFS_B_PARTNUM"
            exit 1
        fi
        if ! $PARTED -s "$DISK" set $ROOTFS_A_PARTNUM legacy_boot off; then
            log "ERROR: Failed to clear legacy_boot on partition $ROOTFS_A_PARTNUM"
            exit 1
        fi
    else
        log "ERROR: Invalid slot: '$SLOT' (expected 'a' or 'b')"
        exit 1
    fi
    log "Primary slot set to: $SLOT"
}

get_state() {
    # $1 = slot (a or b)
    SLOT="$1"
    STATE_FILE="${PERSIST_DIR}/state-${SLOT}"
    if [ -f "${STATE_FILE}" ]; then
        cat "${STATE_FILE}"
    else
        # Safe default: missing file means slot has never been marked bad
        echo "good"
    fi
}

set_state() {
    # $1 = slot (a or b)
    # $2 = state (good or bad)
    SLOT="$1"
    STATE="$2"
    log "Setting state for slot $SLOT to: $STATE"

    STATE_FILE="${PERSIST_DIR}/state-${SLOT}"
    if ! mountpoint -q /persist; then
        log "ERROR: /persist not mounted - state for slot $SLOT NOT persisted"
        return 1
    fi
    if ! persist_is_rw; then
        if ! mount -o remount,rw /persist 2>/dev/null; then
            log "ERROR: failed to remount /persist rw - state for slot $SLOT NOT persisted"
            return 1
        fi
        PERSIST_OPENED_BY_US=1
    fi
    mkdir -p "${PERSIST_DIR}"
    if echo "${STATE}" > "${STATE_FILE}.tmp" && mv "${STATE_FILE}.tmp" "${STATE_FILE}"; then
        sync
        log "Persisted state for slot $SLOT: $STATE"
    else
        log "ERROR: failed to write state file for slot $SLOT"
        rm -f "${STATE_FILE}.tmp"
    fi
    if [ "$PERSIST_OPENED_BY_US" -eq 1 ]; then
        mount -o remount,ro /persist 2>/dev/null || true
        PERSIST_OPENED_BY_US=0
    fi
}

log "Called with: $*"

case "$1" in
    get-primary)
        get_primary
        ;;
    set-primary)
        set_primary "$2"
        ;;
    get-state)
        get_state "$2"
        ;;
    set-state)
        set_state "$2" "$3"
        ;;
    *)
        log "Unknown operation: $1"
        exit 1
        ;;
esac

exit 0
