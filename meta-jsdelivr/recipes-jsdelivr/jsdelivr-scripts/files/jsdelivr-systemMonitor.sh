#!/bin/bash

# Source shared utilities (includes LED functions)
source /usr/bin/jsdelivr-utils.sh

STABLE_MINIMUM=30
NAME=globalping-probe
BOOT_READY_FLAG="/tmp/.jsdelivr_boot_ready"

# Wait for boot to complete before starting to monitor
# This prevents false "container failed" LED during boot sequence
echo "Waiting for boot ready flag..." > /dev/tty1
while [ ! -f "$BOOT_READY_FLAG" ]; do
    sleep 1
done
echo "Boot ready, starting container monitoring" > /dev/tty1

while [ 1 ];
do

RUNNING="$(docker inspect -f '{{.State.Running}}' "$NAME" 2>/dev/null || echo)"
START_RAW="$(docker inspect -f '{{.State.StartedAt}}' "$NAME" 2>/dev/null || echo)"

ts_no_nanos="${START_RAW%%.*}Z"
ts_spaced="${ts_no_nanos%Z}"
ts_spaced="${ts_spaced/T/ }"


to_epoch() {
  date -u -d "$1" +%s 2>/dev/null && return 0
  date -u -D '%Y-%m-%d %H:%M:%S' -d "$1" +%s 2>/dev/null && return 0
  TZ=UTC awk -v s="$1" 'BEGIN{
    split(s,a,/[- :]/);
    if (length(a[1])==0) exit 1;
    print mktime(a[1]" "a[2]" "a[3]" "a[4]" "a[5]" "a[6])
  }' && return 0
  return 1
}

START_TS="$(to_epoch "$ts_spaced")"
CURRENT_TS="$(date -u +%s)"
UP_SECS=$(( CURRENT_TS - START_TS ))


    if [ "$RUNNING" == "true" ]; then
        echo "Container $UP_SECS seconds" > /dev/tty1
        if [ "$UP_SECS" -gt "$STABLE_MINIMUM" ]; then
            echo "Container status is STABLE" > /dev/tty1
            touch /tmp/SYSTEM_STABLE
            touch /tmp/CAN_UPGRADE
            # STABLE: Solid GREEN
            led_container_stable
        else
            echo "Container status is STARTING" > /dev/tty1
            # STARTING: Fast blinking GREEN
            led_container_starting
        fi
    else
        echo "Container status is FAILED!!" > /dev/tty1
        # FAILED: Fast blinking RED
        led_container_failed
    fi

    # Disk space monitoring (informational, logged every 60 seconds)
    MONITOR_COUNT=$((${MONITOR_COUNT:-0} + 1))
    if [ "$MONITOR_COUNT" -ge 30 ]; then
        MONITOR_COUNT=0
        # Check Docker partition usage
        DOCKER_USAGE=$(df /var/lib/docker 2>/dev/null | tail -1 | awk '{print $5}' | tr -d '%')
        if [ -n "$DOCKER_USAGE" ] && [ "$DOCKER_USAGE" -gt 90 ]; then
            echo "WARNING: Docker partition ${DOCKER_USAGE}% full, pruning dangling images" > /dev/tty1
            docker image prune -f 2>/dev/null || true
        elif [ -n "$DOCKER_USAGE" ]; then
            echo "Docker disk: ${DOCKER_USAGE}%" > /dev/tty1
        fi
        # Network connectivity check (informational only)
        if ping -c 1 -W 3 1.1.1.1 >/dev/null 2>&1; then
            echo "Network: OK" > /dev/tty1
        else
            echo "Network: DOWN (informational)" > /dev/tty1
        fi
    fi

    sleep 2

done
