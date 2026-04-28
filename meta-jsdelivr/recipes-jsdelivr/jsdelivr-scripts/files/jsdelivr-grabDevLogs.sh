#!/bin/bash

while :; do
   # Truncate (vs rm+create) so we never have a missing-file race against readers.
   : > /tmp/collector
   date > /tmp/collector
   for n in 1 2 3 4 5 6; do
       [ -r "/dev/vcs${n}" ] && cat "/dev/vcs${n}" >> /tmp/collector
   done

   sed -e 's,\(.\{80\}\),\1\n,g' /tmp/collector > /tmp/log_collector
   sleep 4
done
