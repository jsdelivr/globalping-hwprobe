#!/bin/sh
# RAUC pre-install handler for NanoPi Zero2
#
# This handler is called BEFORE RAUC installs an update to a slot.
# It remounts /persist as read-write so RAUC can write status files.
#
# The post-install handler will remount /persist back to read-only.

LOGGER="/usr/bin/logger"

log() {
    echo "[pre-install] $*" >&2
    $LOGGER -t rauc-pre-install "$*" 2>/dev/null || true
}

log "Pre-install handler started"

# Remount /persist as read-write for RAUC to write status files
if [ -d "/persist" ]; then
    if mount -o remount,rw /persist 2>/dev/null; then
        log "Remounted /persist as read-write"
    else
        log "Warning: Failed to remount /persist as read-write"
    fi

    # Ensure rauc directory exists
    mkdir -p "/persist/rauc"
    log "Ensured /persist/rauc directory exists"
else
    log "Warning: /persist directory not found"
fi

log "Pre-install handler completed"
exit 0
