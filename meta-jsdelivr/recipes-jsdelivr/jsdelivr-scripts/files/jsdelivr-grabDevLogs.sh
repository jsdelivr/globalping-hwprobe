#!/bin/bash

while [ 1 ]; do
   rm /tmp/collector
   date > /tmp/collector
   cat /dev/vcs1 >> /tmp/collector
   cat /dev/vcs2 >> /tmp/collector
   cat  /dev/vcs3 >> /tmp/collector
   cat  /dev/vcs4 >> /tmp/collector
   cat  /dev/vcs5 >> /tmp/collector
   cat  /dev/vcs6 >> /tmp/collector

   echo "`cat /tmp/collector | sed -e 's,\(.\{80\}\),\1\\n,g' `" > /tmp/log_collector
   sleep 4
done
