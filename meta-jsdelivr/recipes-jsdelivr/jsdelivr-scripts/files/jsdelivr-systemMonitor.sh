#!/bin/bash


echo "none"  >  /sys/class/leds/nanopi\:green\:pwr/trigger

STABLE_MINIMUM=30

while [ 1 ];
do

    RUNNING=$(docker inspect --format='{{.State.Running}}' globalping-probe)
    START=$(docker inspect --format='{{.State.StartedAt}}' globalping-probe)
    START_TIMESTAMP=$(date --date=$START +%s)
    CURRENT_TIMESTAMP=$(date  +%s)
    UP_SECS=$(($CURRENT_TIMESTAMP-$START_TIMESTAMP))


    if [ "$RUNNING" == "true" ]; then
        echo "Container $UP_SECS seconds" > /dev/tty1
        if [ "$UP_SECS" -gt "$STABLE_MINIMUM" ]; then
            echo "Container status is STABLE" > /dev/tty1
            touch /tmp/SYSTEM_STABLE
            #echo 1 >  /sys/class/leds/nanopi\:green\:pwr/shot
             echo "none"  >  /sys/class/leds/nanopi\:green\:pwr/trigger
             echo "default-on" > /sys/class/leds/nanopi\:blue\:status/trigger
        else
            echo "Container status is UNSTABLE" > /dev/tty1
            echo "none"  >  /sys/class/leds/nanopi\:green\:pwr/trigger
            echo "timer" >  /sys/class/leds/nanopi\:blue\:status/trigger
            sleep 0.5
            echo 100 >  /sys/class/leds/nanopi\:blue\:pwr/delay_on
            echo 500 >  /sys/class/leds/nanopi\:blue\:pwr/delay_off
        fi
    else
        echo "Container status is NOT running!!" > /dev/tty1
        echo "none"  >  /sys/class/leds/nanopi\:blue\:status/trigger
        echo "default-on" > /sys/class/leds/nanopi\:green\:pwr/trigger
    fi


    sleep 2

done
