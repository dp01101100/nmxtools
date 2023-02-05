# Script to check for data on contiguous days based on file name.
awk 'BEGIN{
   yc=0;mc=0;dc=0;n=split("31 28 31 30 31 30 31 31 30 31 30 31",days)
   for(i=1;i<=n;i++) days[i]=0+days[i]
   deb=0
}
{
   sta=substr($1,1,4)
   yy=0+substr($1,5,2); mm=0+substr($1,7,2); dd=0+substr($1,9,2)
   str=sprintf("do %d %d %d",yy,mm,dd)
   if (dc<=0) {
      dc=dd; mc=mm; yc=yy
      print "Start:",yc,mc,dc
   }
   if (dc == dd && mc == mm && yc == yy) next ## Repeat on same day ok
   if (yc == yy && mc == mm && dd == dc+1) {
      ## Next day ok
      dc = dd; if (deb) print str,"-- next day"; next
   }
   if (yc == yy && mc == mm) {
      ## Same year, month but day gap
      if (dc+1 == dd-1) str=dc+1 ""; else str=dc+1 "-" dd-1
      print "gap",yy,mm,str; dc = dd; next
   }
   if (yc == yy && mc < mm) {
      ## Same year, possible month change -- check for gap
      if (yy%4 == 0) days[2]=29; else days[2]=28
      if (dc < days[mc]) {
         ## Gap at end of previous month
         print "gap",yy,mc,dc+1 "-" days[mc]
      }
      if (mm == mc+1) {
         ## Next month -- OK
	 if (dd > 1) print "gap",yy,mm,"1-" dd-1
         mc = mm; dc = dd; if (deb) print str,"-- next month,day"; next
      }
      if (mm > mc+1) {
         ## Multi-month gap
	 for(i=mc+1;i<mm;i++) print "gap",yy,i,"1-" days[i]
	 if (dd>1) print "gap",yy,mm,"1-" dd-1
	 mc = mm; dc = dd; next
      }
      print str,"*** fell through; logic error ***"
   }
   if (mm == 1 && yy == yc+1) {
      ## Next year, month==1, check for gap at start
      yc = yy; mc = 1
      for(i=1;i<dd;i++) print "gap",yy,1,i
      dc = dd; next
   }
   if (yy == yc+1 && mm > 1) {
      ## Multi-month gap at begin of new year month
      if (yy%4 == 0) days[2]=29; else days[2]=28
      for(i=1;i<mm;i++) print "gap",yy,i,"1-" days[i]
      for(i=1;i<days[mm];i++) print "gap",yy,mm,i
      yc = yy; mc = mm; dc = dd
      if (deb && mm==1 && dd==1) print str,"-- next year,month,day"; next
   }
}
END{
   print "End:",yc,mc,dc
}'
