#! /bin/sh
#usage:  doextract [-store xxxx yyyy | [-mseed dir] [-sn store#] yyyy mm [dd]]
#  apollo server must be running on port 8080
#  xxxx is the store file and yyyy is the station name
#  store file and mseed dir must be full path names (apollo server has no
#  working directory)
#by G. Helffrich/U. Bristol 25 May 2007, updated 14 July 2011
tmp=/tmp/tmp$$
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
while [ $# -gt 0 ]; do
   case "$1" in
      -sn) sn=$2; shift 2;;
      -mseed) dir="$2"
	 [ -d $dir ] || { echo "**MSEED data directory unreadable."; exit 1;}
	 echo MSEED='"'${dir}'"' > .mseed
	 shift 2
         ;;
      *) [ -f .nmxstore ] && . .nmxstore
	 if [ -z "$NMXSTORE" ]; then
	    echo "**No store defined and no -sn given, quitting."
	    exit 1
	 fi
	 [ -f .mseed ] && . .mseed
	 if [ -z "$MSEED" ]; then
	    echo "**No bulk mseed data defined, quitting."
	    exit 1
	 fi
	 sn=$NMXSTORE dir=$MSEED sta=$NMXSTA
	 [ -d $dir ] || { echo "**MSEED data directory unreadable."; exit 1;}
	 break
	 ;;
   esac
done
yy=$1; mm=`echo $2 | awk '{printf "%02d",$1}'`
y0=`echo $yy | awk '{printf "%02d",$1%100}'`
function ext() {
perl - $1 $2 $3 $4 $5 $6 << '__END__'
# =========================
package NMX::Scripts;

use Time::Local;

# =========================
sub getChannel
{
    ( $serialNumber, $channelnum ) = @_;
    $channel = sprintf ("taurus_%04d/band/timeSeries%d/", $serialNumber, $channelnum);
    return $channel;
}

# =========================
sub getURL
{
    ( $ip_address, $startTime, $duration, $serialNumber, $channel ) = @_;
    my $urlString = 
       sprintf("http://%s/playback/download/",$ip_address) . "?" .
       sprintf("channels=%s&dataType=TimeSeries&dataFormat=MiniSEED&startTime=%s&duration=%d_d", $channel, $startTime, $duration);
    return $urlString;
}
# =========================
sub getTimeString
{
    ( $inputTime ) = @_;
    @part = split(/_/, $inputTime);
    @ymd = split(/\//, @part[0]);
    @hms = split(/:/, @part[1]);
    my $date = sprintf( "%04d-%02d-%02d %02d:%02d:%02d",
        @ymd[0], @ymd[1], @ymd[2], @hms[0], @hms[1], @hms[2] );
    return $date;
}

# =========================
sub getFiles
{
    ( $ip_address, $serialNumber, $startTime, $duration, $interval, $fn ) = @_;

    my $start = getTimeString($startTime);
    my @sfx = ( "", "BHZ", "BHN", "BHE" );
        for (my $num = 1; $num < 4; $num++) {
			my $channel = getChannel($serialNumber, $num + "");
			my $url = getURL($ip_address, $start, $interval, $serialNumber, $channel);
			my $ofn = $fn . "." . $sfx[$num];
			# print "URL: " . $url . "\n  to $ofn\n";
			# print "cmd: " . " -o " . $ofn . " " . $url . "\n";
			my @args = ("curl", "-sS", "-o", $ofn, "$url");
			my $res = system(@args);

			if ($res == 0) {
				my $head, $size = (stat($ofn))[7];
				if ($size < 4096) {
				   open(DF, $ofn) or $res = -1;
				   if ($res == 0) {
				      read(DF,$head,6) or $res = -1;
				   }
				   if ($res == 0 &&
				      $head =~ /<[hH][tT][mM][lL]>/) {
				      $res = -1;
				      unlink($ofn);
				   }
				   close(DF);
				}
				if ($res == 0) {
				   print sprintf("Got file: %s\n", $ofn);
				   # system("ls -l " . $ofn);
				}
			}
			if ($res != 0){print "Error getting $ofn\n";}
        }
}

# =========================
( $ip_address, $serialNumber, $startTime, $duration, $interval, $fn ) = @ARGV;

getFiles($ip_address, $serialNumber, $startTime, 1, 1, $fn);
__END__
}
function rename() { ## Rename files to actual start time of data in them
   ## 1: dir 2: file prefix 3: result
   for c in BHE BHN BHZ ; do
      f=${1}/${2}.$c
      if [ -s $f ]; then
         mseedtime $f | while read sta loc chan yy mn dd hh mm ss th ; do
            fn=${1}/`echo $sta $yy $mn $dd $hh $mm $ss |
               awk '{printf "%s%02d%02d%02d%02d%02d%02d",
                  $1,$2%100,$3,$4,$5,$6,$7}'`.${chan}
            [ $f = $fn ] || mv $f $fn
            echo $fn
         done
      else
         /bin/rm -f $f ; echo "**No data for $yy $mm $dd" > /dev/tty
      fi
   done
}
function msort() { ## Sort data in files into ascending time order
   ## 1: temp file prefix 2: output file prefix
   for c in BHE BHN BHZ ; do
      mseedsort -b 512 ${1}.$c |
         sort -k 6 -k 7 -k 8 -k 9 -k 10 -k 11 -k 12 |
         awk '{print $5}' |
         mseedsort -b 512 -o ${2}.$c ${1}.$c
      echo unsorted: ${1}.$c sorted: ${2}.$c 
   done
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
   for d in `echo $nm | awk '{for(i=1;i<=$1;i++) print i}'` ; do
      dd=`echo $d | awk '{printf "%02d",$1}'`
      dur=1
      pfx="${sta}${y0}${mm}${dd}000000"
      ext localhost:8080 $sn \
         $yy/$mm/${dd}_00:00:00 $dur $dur $tmp
      msort $tmp /tmp/$pfx
      /bin/rm -f $tmp.BH[ENZ]
      nm=`rename /tmp $pfx FNAME`
      for f in $nm ; do
         echo processing: $f
         make_qseed -l -b 512 -S ${sta} -o $dir $f
         /bin/rm -f $f
      done
   done
elif [ $# -eq 3 ]; then
   dd=`echo $3 | awk '{printf "%02d",$1}'`
   dur=1
   pfx="${sta}${y0}${mm}${dd}000000"
   ext localhost:8080 $sn \
         $yy/$mm/${dd}_00:00:00 $dur $dur $tmp
   msort $tmp /tmp/$pfx
   /bin/rm -f $tmp.BH[ENZ]
   nm=`rename /tmp $pfx FNAME`
   for f in $nm ; do
      make_qseed -l -b 512 -S ${sta} -o $dir $f
      /bin/rm -f $f
   done
else
   echo "$0: usage:  doextract [-store xxxx yyyy |"
   echo "               [-mseed dir] [-sn store#] yyyy mm [dd]]"
   echo "       where -store xxxx yyyy sets the store file for station yyyy"
   echo "          to the file xxxx; must be set once to change store/station"
   echo "          combination.  Only option allowed if used."
   echo "       -sn store# -- optional store number if not able to determine"
   echo "          from the store file name (see -store)"
   echo "       -mseed dir -- mseed data directory to save extracted data;"
   echo "          must be given once, and then remembered for future"
   echo "          extraction"
   echo "       and yyyy mm [dd] - year, month and (optional) day for data"
   echo "          extraction; if no day, all days in month extracted."
   echo "   An Apollo Lite server must be running on port 8080"
fi
