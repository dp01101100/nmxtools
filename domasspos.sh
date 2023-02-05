#! /bin/sh
#usage:  domasspos [-store xxxx yyyy | [-sn store#] yyyy mm [dd]]
#  apollo server must be running on port 8080
#  xxxx is the store file and yyyy is the station name
#by G. Helffrich/U. Bristol 31 Mar. 2008
lsfn=/usr/local/lib/leapseconds dir=/tmp
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
      -dir) dir=$2; shift 2;;
      *) [ -f .nmxstore ] && . .nmxstore
	 if [ -z "$NMXSTORE" ]; then
	    echo "**No store defined and no -sn given, quitting."
	    exit 1
	 fi
	 sn=$NMXSTORE sta=$NMXSTA
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
sub timeInMillis
{
    ( $inputTime ) = @_;

    $inputTime =~ s/(^\s*|\s*$)//g;
    if ($inputTime =~ /([0-9][0-9][0-9][0-9])[\-\/\.]([0-9][0-9])[\-\/\.]([0-9][0-9])[ _T\.]([0-9][0-9])[:\-\.]([0-9][0-9])[:\-\.]([0-9][0-9])($|\.[0-9]+)/)
    {
      my $value = timegm($6, $5, $4, $3, $2 - 1, $1);
      my $date = sprintf( "%04d-%02d-%02d_%02d:%02d:%02d", $1, $2, $3, $4, $5, $6 );
      $fraction =~ s/0\.//;
      $date = sprintf( "%s.%09d", $date, $fraction );
      my $valueMs = sprintf ("%d%03d", $value, $fraction / 1000000);
      return $valueMs
    }
    else
    {
      return 0;
    }
}

# =========================
sub durationInMillis
{
    ( $duration ) = @_;
    return $duration * 1000;
}

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
    ( $ip_address, $startTime, $duration, $serialNumber ) = @_;
    my $urlString = 
       sprintf("http://%s/playback/download",$ip_address) . "?" .
       sprintf("dataType=StateOfHealth&dataFormat=EnvironmentSOH(csv)&startMillis=%s&duration=%d_s", $startTime, $duration / 1000);
    return $urlString;
}
# =========================
sub getTimeString
{
    ( $inputTime ) = @_;
    $inputTime =~ s/(^\s*|\s*$)//g;
    $seconds = $inputTime / 1000;
    $fraction += $inputTime % 1000;
    $fraction /= 1000;
    $units = "ms";
    my ( $sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst ) = gmtime($seconds);
    $mon++;
    $year += 1900;
    my $date = sprintf( "%02d-%02d-%02d_%02d_%02d_%02d",
        $year, $mon, $mday, $hour, $min, $sec );
    return $date;
}

# =========================
sub getFiles
{
    ( $ip_address, $serialNumber, $startTime, $duration, $interval, $fn ) = @_;

    $endTime = $startTime + $duration;
    while($startTime < $endTime){
        if ($startTime + $interval > $endTime) {
           $interval = $endTime - $startTime;
        }
	my $url = getURL($ip_address, $startTime, $interval, $serialNumber);
	my $ofn = $fn . ".csv";
	print "URL: " . $url . "\n  to $ofn\n";
	print "cmd: " . " -o " . $ofn . " " . $url . "\n";
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
		}
	}
	if ($res != 0) {print "Error getting $ofn\n";}
	   
        $startTime = $startTime + $interval;
    }
}

# =========================
( $ip_address, $serialNumber, $startTime, $duration, $interval, $fn ) = @ARGV;
my $startTimeInMs = timeInMillis($startTime);
my $durationInMs = durationInMillis($duration);
my $intervalInMs = durationInMillis($interval);

getFiles($ip_address, $serialNumber, $startTimeInMs, $durationInMs, $intervalInMs, $fn);
__END__
}
function duration() { ## Duration that accounts for leap second.
## 1: year 2: day 3: arg 4: file
   if [ $2 -eq $3 -a -f $4 ]; then
      awk "BEGIN{corr=0}
         /^Leap[     ]*${1}[        ]*((Jun)|(Dec))[        ]*${3}[        ]/{"'
            if ($6 == "+") corr=1; else corr=-1}
         END{print 86400+corr}' $lsfn
   else
      echo 86400
   fi
}
function split() { ## Split data out of .csv file
   ## 1: dir 2: file prefix 3: station name
   f=${1}/${2} suffix='MPZ MPN MPE'
   if [ -s $f.csv ]; then
      awk -F, 'BEGIN{fn="'"${f}"'"; n=split("'"${suffix}"'",f," ")}
         NR>1{for(i=1;i<=3;i++) {of=fn "." f[i]; print $1,$2,$(6+i) > of}}' \
	    $f.csv
      for sfx in $suffix ; do
         fn=`awk '{
	    nymd=split($2,ymd,"-");nhms=split(substr($3,1,length($3)-1),hms,":")
            printf "%02d%02d%02d%02d%02d%02d",
                  ymd[1]%100,ymd[2],ymd[3],hms[1],hms[2],hms[3]
	    exit}' $f.$sfx`
	 echo ${3}$fn
      done
#     /bin/rm -f $f.csv
   else
      /bin/rm -f $f.csv ; echo "**No data for $yy $mm $dd" > /dev/tty
   fi
}
if [ $# -eq 2 ]; then
   case $mm in
   01) nm=31 ls=0  ;;
   02) nm=`echo $yy |
          awk '{if($1%4 == 0 && $1%400 != 0) print 29; else print 28}'` ls=0 ;;
   03) nm=31 ls=0  ;;
   04) nm=30 ls=0  ;;
   05) nm=31 ls=0  ;;
   06) nm=30 ls=30 ;;
   07) nm=30 ls=0  ;;
   08) nm=31 ls=0  ;;
   09) nm=30 ls=0  ;;
   10) nm=31 ls=0  ;;
   11) nm=30 ls=0  ;;
   12) nm=31 ls=31 ;;
   *) echo "$0: Invalid month $mm" ; exit 1 ;;
   esac
   for d in `echo $nm | awk '{for(i=1;i<=$1;i++) print i}'` ; do
      dd=`echo $d | awk '{printf "%02d",$1}'`
      dur=`duration $yy $dd $ls $lsfn`
      pfx="${sta}${y0}${mm}${dd}000000"
      ext localhost:8080 $sn \
         $yy/$mm/${dd}_00:00:00 $dur $dur /tmp/$pfx
      fnm=(`split /tmp $pfx`) sfx=(MPE MPN MPZ)
      for f in 0 1 2 ; do
	 if=/tmp/${pfx}.${sfx[$f]}
         if [ -s $if ]; then
	    masspos -sta ${sta} -time `awk '{print $2,$3; exit}' $if` \
	       -c ${sfx[$f]} -o ${dir}/${sta}${fnm[$f]}.${sfx[$f]} < $if
	 fi
	 /bin/rm -f $if
      done
   done
elif [ $# -eq 3 ]; then
   dd=`echo $3 | awk '{printf "%02d",$1; exit}'`
   case $3$4 in
      0630|630) ls=30 ;;
      1231) ls=31 ;;
      *) ls=0 ;;
   esac
   declare -a fnm sfx
   dur=`duration $yy $dd $ls $lsfn`
   pfx="${sta}${y0}${mm}${dd}000000"
   ext localhost:8080 $sn \
         $yy/$mm/${dd}_00:00:00 $dur $dur /tmp/$pfx
   nm=(`split /tmp $pfx`) sfx=(MPZ MPN MPE)
   for f in 0 1 2 ; do
      if=/tmp/${pfx}.${sfx[$f]}
      if [ -s $if ]; then
	 masspos -sta ${sta} -time `awk '{print $2,$3; exit}' $if` \
	    -c ${sfx[$f]} -o ${dir}/${sta}${nm[$f]}.${sfx[$f]} < $if
      fi
      /bin/rm -f $if
   done
else
   echo "$0: usage:  domasspos [-store xxxx zzzz |"
   echo "               [-sn store#] [ -dir aaa ] yyyy mm [dd]]"
   echo "       where -store xxxx zzzz sets the store file for station zzzz"
   echo "          to the file xxxx; must be set once to change store/station"
   echo "          combination.  Only option allowed if used."
   echo "       -sn store# -- optional store number if not able to determine"
   echo "          from the store file name (see -store)"
   echo "       -dir aaa -- optional directory to place files (default: /tmp);"
   echo "          will be named 'aaa/zzzzyymmddhhmmss.MP[ENZ]' based on first"
   echo "          sample time"
   echo "       and yyyy mm [dd] - year, month and (optional) day for data"
   echo "          extraction; if no day, all days in month extracted."
   echo "   An Apollo Lite server must be running on port 8080"
fi
