#! /bin/sh
#usage:  dogetpos [-p] [-store xxxx yyyy | [-sn store#] yyyy mm [dd]]
#  apollo server must be running on port 8080
#  xxxx is the store file and yyyy is the station name
#by G. Helffrich/U. Bristol 14 Nov 2007; updated 1 Apr. 2008
opt_p=0 cont=1
if [ "$1" = "-store" ]; then
   pfx="http://localhost:8080/pages/central/storeSelector.page"
   sfx="storeFile=$2" sta=$3
   tmp=/tmp/tmp$$
   curl -sS ${pfx}?${sfx} > $tmp 2>&1 
   if egrep -q 'Connection refused' $tmp ; then
      echo "**Store selection failed -- apollo running?"
   elif egrep -q 'id="message".*Improper file selection' $tmp ; then
      echo "**Store selection failed."
   elif egrep -q 'Connect failed' $tmp ; then
      echo "**Store selection failed -- apollo running?"
   else
      echo "**Store selection succeeded."
      sname=`basename $2`
      sn=`echo $sname | sed -e 's/.*_\([0-9][0-9][0-9][0-9]\)_.*/\1/'`
      if [ "$sn" != "$sname" ]; then
	 echo NMXSTORE=$sn NMXSTA=$sta > .nmxstore
      fi
   fi
   /bin/rm -f $tmp
   exit
fi
while [ $cont -ne 0 ]; do
   case "$1" in
      -p) opt_p=1; shift;;
      -sn) sn=$2; shift 2; cont=0;;
      *) [ -f .nmxstore ] && . .nmxstore
         if [ -z "$NMXSTORE" ]; then
            echo "**No store defined and no -sn given, quitting."
	    exit 1
         fi
         sn=$NMXSTORE sta=$NMXSTA cont=0;;
   esac
done
yy=$1; mm=`echo $2 | awk '{printf "%02d",$1}'`
y0=`echo $yy | awk '{printf "%02d",$1%100}'`
function ext() {
   curl -sS "http://${1}/playback/download?channels=taurus_${2}/band/timeSeries1/&dataType=TimeSeries&dataFormat=ASCII&startTime=${3}-${4}-${5} ${6}:${7}:${8}&duration=1 s" | sed -e 's///g' |
   awk 'BEGIN{reftek='"${opt_p}"'}
      func dms(val,n,p,m){
	 if (val<0) {sfx=m; val=-val} else sfx=p
	 dd=int(val); mm=int((val-dd)*60); ss=(val-dd-mm/60)*3600
	 return sprintf("%s %*d:%02d:%05.2f",sfx,n,dd,mm,ss)
      }
      /Latitude:/{n++;lat=0+$2}/Longitude:/{n++;lon=0+$2}/Elevation:/{n++;el=0+$2}
      END{
	 if(n>0){
	    if(reftek) printf "             POSITION:%-13s %-14s EL: %d\n", \
	       dms(lat,2,"N","S"),dms(lon,3,"E","W"),el
	    else print lat,lon,el
         }
      }'
}
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
      for hh in 00 06 12 18 ; do
         ext localhost:8080 $sn $yy $mm $dd $hh 05 00
      done
   done
elif [ $# -eq 3 ]; then
   dd=`echo $3 | awk '{printf "%02d",$1}'`
#  ext localhost:8080 $sn $yy $mm $dd $hh $mn $ss
   for hh in 00 01 02 03 04 05 06 07 08 09 10 11 \
	     12 13 14 15 16 17 18 19 20 21 22 23 ; do
         ext localhost:8080 $sn $yy $mm $dd $hh 05 00
   done
else
   echo $0:  Invalid number of arguments.
fi
