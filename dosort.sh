#!/bin/sh
#  dosort -- shell script to process a list of file names, sort mseed packets
#            into ascending time order, and write an output file with packets
#            in proper order.
#
#  Reads file names from standard input.
#  Single command line arg is output directory.  Does not destroy any input
#     file.  Renames file to correspond to first sample time.

tmp=/tmp/tmp$$.msd dir=${1:-.} blk=${2:-4096}

while read f; do
   mseedsort -b ${blk} $f |
      sort -k 6 -k 7 -k 8 -k 9 -k 10 -k 11 -k 12 |
      awk '{print $5}' |
      mseedsort -b ${blk} -o $tmp $f
#02697 -- BHZ YY 2012 01 04 00 00 09 2000
   fn=`mseedtime $tmp |
      awk '{yr=substr($5,3)
         printf "%s%s%s%s%s%s%s.%s",$1,yr,$6,$7,$8,$9,$(10),$3}'`
   mv $tmp ${dir}/$fn
done
/bin/rm -f $tmp
