#!/bin/bash

# Hard-fail if the watchdog device is missing so systemd surfaces the issue
# rather than silently running a kicker that never reaches the hardware.
if [ ! -c /dev/watchdog0 ]; then
    echo "FATAL: /dev/watchdog0 not present, refusing to run watchdog kicker" >&2
    exit 1
fi

exec 5> /dev/watchdog0


while [ 1 ];
do
    echo "1" >&5
    sleep 1
done
