#!/bin/bash


exec 5> /dev/watchdog0


while [ 1 ];
do
    echo "1" >&5
    sleep 1
done
