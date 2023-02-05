#!/bin/sh
#  Calculate average station position from GPS fixes.  Reproduces calculation
#  done in the PASSCAL program "position" written by Jim Fowler in 1994.  Uses
#  robust statistics to discard bad fixes to get a reliable station position.
awk 'BEGIN{tmp="/tmp/tmp'$$'"; debug=0}
   func abs(x){if (x>0) return x; else return 0-x}
{ # YYYY/MM/DD hh:mm:ss lat lon [elev]
   n+=1; lat[n]=0+$3; lon[n]=0+$4; el[n]=0+$5
   yymmdd=$1; hhmmss=$2
   if (n==1) fst=yymmdd " " hhmmss
   if (lat[n] == 0.0 && lon[n] == 0.0) {
      n = n-1
   } else {
      sumlat += lat[n]; sumlon += lon[n]; sumel  += el[n]
   }
}
END{
   if (n<=0) {print "**No (nonzero) fixes, no position!"; exit 1}
   lst=yymmdd " " hhmmss
   printf "Time of first position: %s\nTime of last position:  %s\n",fst,lst

   mlat = sumlat/n; mlon = sumlon/n; mel = sumel/n
      fac = cos(mlat*3.1415627/180.)
   var = 0; for(i=1;i<=n;i++) {
      dlat = lat[i]-mlat; dlon = fac*(lon[i]-mlon)
      var += dlat*dlat + dlon*dlon
   }
   if (n>1) var /= n-1; else var = 0; dev = 111194.0*sqrt(var)

   printf "Average position %9.5f %9.5f\n",mlat,mlon
   printf "Number of positions %d, standard dev. %10.2f m\n",n,dev
   if (sumel>0) {
      for(i=1;i<=n;i++) evar += (el[i]-mel)*(el[i]-mel) 
      if (n>1) evar /= n-1; else evar = 0; evar = sqrt(evar)
      printf "Elevation average: %f std dev: %f\n",mel,evar
   }

   ## /* Robust statistics start here.  Sort first on longitude, then lat. */
   if (n>1) {
      cmd = "sort -g -k 1,1 " tmp
      print lon[1] > tmp; for(i=2;i<=n;i++) print lon[i] >> tmp
         fflush(tmp); close(tmp)
      i=0; while(cmd | getline x) slon[++i] = 0+x; close(cmd)
      if (i != n) printf "**Trouble from sort: %d != %d! (lon)\n", i, n > "/dev/tty"

      print lat[1] > tmp; for(i=2;i<=n;i++) print lat[i] >> tmp
         fflush(tmp); close(tmp)
      i=0; while (cmd | getline x) slat[++i] = 0+x; close(cmd)
      if (i != n) printf "**Trouble from sort: %d != %d! (lat)\n", i, n > "/dev/tty"

      ## /* Median value is middle of sorted values */
      if (n%2) {
         medlat = slat[int(n/2)+1]; medlon = slon[int(n/2)+1];
      } else {
	 medlat = (slat[int(n/2)] + slat[int(n/2)+1])/2
	 medlon = (slon[int(n/2)] + slon[int(n/2)+1])/2
      }

      ## /* Calculate median sigma */
      for(i=1;i<=n;i++) {
         siglat += abs(lat[i] - medlat); siglon += abs(lon[i] - medlon)
      }
      medsiglat = siglat*sqrt(2.0)/n; medsiglon = siglon*sqrt(2.0)/n
      if (debug) {
	 printf "**Debug: position %9.5f, %9.5f\n", medlat, medlon
	 printf "**Debug: medsiglat, medsiglon %f %f, n %d\n",medsiglat,medsiglon,n
      }

      ## /* Discard values > 1 sigma */
      lolat = 0; hilat = 0; lolon = 0; hilon = 0
      for(i=1;i<=n;i++){
         if (slat[i] >= medlat-medsiglat && lolat == 0) lolat = i
         if (slat[i] >= medlat+medsiglat && hilat == 0) hilat = i
         if (slon[i] >= medlon-medsiglon && lolon == 0) lolon = i
         if (slon[i] >= medlon+medsiglon && hilon == 0) hilon = i
      }
      if (lolat == 0) lolat = 1; if (hilat == 0) hilat = n
      if (lolon == 0) lolon = 1; if (hilon == 0) hilon = n

      ## /* Recalculate variance with reduced set of points */
      if (debug) printf "**Debug: lat (lo,hi) lon (lo,hi) (%d,%d) (%d,%d)\n",lolat,hilat,lolon,hilon
      if (lolat < lolon) lo = lolon; else lo = lolat
      if (hilat > hilon) hi = hilon; else hi = hilat
      nrob = hi-lo+1; sumlat = 0; sumlon = 0; sumel = 0
      for(i=lo;i<=hi;i++) {
         sumlat += slat[i]; sumlon += slon[i]
      }
      mlat = sumlat/nrob; mlon = sumlon/nrob; sumel = sumel/nrob
         fac = cos(mlat*3.1415627/180.)
      var = 0; for(i=lo;i<=hi;i++) {
         dlat = slat[i]-mlat; dlon = fac*(slon[i]-mlon)
         var += dlat*dlat + dlon*dlon
      }
      if (nrob>1) var /= nrob-1; else var = 0
      dev = 111194.0*sqrt(var)
      printf "MEDIAN position %9.5f, %9.5f\n", medlat, medlon
      printf "%d outliers (> 1 L1-sigma from median) removed\n", n-nrob
      printf "New average position %9.5f, %9.5f\n", mlat, mlon
      printf "Number of positions %d, new std. dev. %10.2f m\n",nrob,dev
      system("/bin/rm " tmp)
   }
}'
