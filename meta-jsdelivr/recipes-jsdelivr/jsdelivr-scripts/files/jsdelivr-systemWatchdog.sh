#!/bin/bash

COUNTER=0
(( TTL_MAX= 60 * 5  ))
LAST_CHANCE=0

exec 4> /dev/watchdog1


while [ 1 ];
do
    COUNTER=$((COUNTER+1))
    echo "System WatchDog counter is :$COUNTER   and Max is:$TTL_MAX " > /dev/tty2
    if [ "$COUNTER" -gt "$TTL_MAX" ]; then
        echo "Container status is faulty" > /dev/tty2
        if ["$LAST_CHANCE" -gt "0"]; then
            echo "Container recover attempt failed, resorting to full system reb                                                                                                                                                             oot"  > /dev/tty2
            while :; do  sleep 2; done
        fi
        echo "1" >&4
        echo "Trying to recover container"  > /dev/tty2
        docker kill  globalping-probe
        echo "1" >&4
        docker kill  globalping-probe
        echo "1" >&4
        docker ps -a > /dev/tty2 > /dev/tty2
        echo "1" >&4
        docker rm globalping-probe > /dev/tty2
        echo "1" >&4
        COUNTER=0
        LAST_CHANCE=$((LAST_CHANCE+1))
    else

        if [ -f /tmp/SYSTEM_STABLE ]; then
            echo "Container status is ok"  > /dev/tty2
            rm /tmp/SYSTEM_STABLE
            COUNTER=0
            LAST_CHANCE=0
        fi

    fi

    echo "1" >&4

    sleep 1

done

