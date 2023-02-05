#! /bin/sh
#usage:  docheck yyyy mm [dd]
dir=mseed yy=$1
mm=`echo $2 | awk '{printf "%02d",$1}'` y0=`echo $yy | awk '{printf "%02d",$1}'`
if [ $# -eq 2 ]; then
   case $mm in
   01) nm=31 ;;
   02) nm=`echo $yy |
          awk '{if($1%4 == 0 && $1%400 != 0) print 29; else print 28}'` ;;
   03) nm=31 ;;
   04) nm=30 ;;
   05) nm=31 ;;
   06) nm=30 ;;
   07) nm=30 ;;
   08) nm=31 ;;
   09) nm=30 ;;
   10) nm=31 ;;
   11) nm=30 ;;
   12) nm=31 ;;
   *) echo "$0: Invalid month $mm" ; exit 1 ;;
   esac
   mo=`echo $mm | awk '{printf "%02d",$1}'`
   for d in `echo $nm | awk '{for(i=1;i<=$1;i++) print i}'` ; do
      dd=`echo $d | awk '{printf "%02d",$1}'`
      for c in Z N E; do 
         for f in $dir/SYRA${y0}${mm}${dd}*.BH$c ; do
	    [ -f $f ] && check_seed -B 512 $f
	 done
      done
   done
elif [ $# -eq 3 ]; then
   dd=`echo $3 | awk '{printf "%02d",$1}'`
   for c in Z N E; do check_seed -B 512 $dir/SYRA${y0}${mm}${dd}*.BH$c; done
else
   echo "$0: usage: docheck yyyy mm [dd]"
   echo "    where yyyy mm [dd] are year, month and optional day"
fi
