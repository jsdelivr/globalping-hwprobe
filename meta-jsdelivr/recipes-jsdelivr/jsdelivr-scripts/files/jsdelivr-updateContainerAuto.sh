#!/bin/bash

# Source shared utilities (includes LED functions)
source /usr/bin/jsdelivr-utils.sh

echo "JSDELIV AUTO Update start" > /dev/tty5

# Set LED to fast green blinking to indicate update in progress
led_container_starting

# Pause monitoring + reboot scripts and replace systemWatchdog with a dumb
# watchdog kicker for the duration of the docker pull. If THIS script dies
# abruptly (SIGKILL, OOM, panic) before reaching the resume path at the
# bottom, those processes would stay frozen forever and keepWatchdogHappy
# would feed /dev/watchdog0 indefinitely while the probe was dead.
# Register a trap so any exit path restores normal state.
auto_update_cleanup() {
    killall jsdelivr-keepWatchdogHappy.sh 2>/dev/null
    killall -CONT jsdelivr-mandatoryReboot.sh 2>/dev/null
    killall -CONT jsdelivr-systemMonitor.sh 2>/dev/null
    # systemWatchdog respawns via its systemd unit (Restart=on-failure)
}
trap auto_update_cleanup EXIT INT TERM HUP

echo "STOPING the MANDATORY reboot script" > /dev/tty5
killall -STOP jsdelivr-mandatoryReboot.sh
killall -STOP jsdelivr-systemMonitor.sh


killall  -9 jsdelivr-systemWatchdog.sh
sleep 1
/usr/bin/jsdelivr-keepWatchdogHappy.sh &

CONTAINERS=$(docker ps -aq 2>/dev/null)
[ -n "$CONTAINERS" ] && docker stop $CONTAINERS

echo "Initiate image download" > /dev/tty5

if ! docker pull globalping/globalping-probe:latest; then
    echo "Image download FAILED" > /dev/tty5
    # We stopped containers before the pull. If the pull fails the device
    # would otherwise sit dark until the watchdog reboots it. Restart any
    # containers that were running so the probe stays online with the
    # existing local image; startWorld's main loop will keep them alive.
    if [ -n "$CONTAINERS" ]; then
        echo "Restarting previously-running containers with existing image..." > /dev/tty5
        for cid in $CONTAINERS; do
            docker start "$cid" >/dev/null 2>&1 || \
                echo "WARNING: could not restart $cid" > /dev/tty5
        done
    fi
    # trap will run cleanup on exit
    exit 1
fi

echo "Image download FINISHED" > /dev/tty5

sync

echo "Main image repo update finished" > /dev/tty5

echo "JSDELIV AUTO Update FINISHED" > /dev/tty5
echo "Resuming the MANDATORY reboot script" > /dev/tty5
# Cleanup is handled by the EXIT trap; no need to duplicate here.

# Restore LED to stable state (systemMonitor will take over after resume)
led_container_stable
