C     julday -- Return julian day number given month, day year.
C
      FUNCTION JULDAY(MM,ID,IYYY)
      PARAMETER (IGREG=15+31*(10+12*1582))
      IF (IYYY.LT.0) IYYY=IYYY+1
      IF (MM.GT.2) THEN
        JY=IYYY
        JM=MM+1
      ELSE
        JY=IYYY-1
        JM=MM+13
      ENDIF
      JULDAY=INT(365.25*JY)+INT(30.6001*JM)+ID+1720995
      IF (ID+31*(MM+12*IYYY).GE.IGREG) THEN
        JA=INT(0.01*JY)
        JULDAY=JULDAY+2-JA+INT(0.25*JA)
      ENDIF
      RETURN
      END

C     getday  --  Given year and day number in year, return month and day
C                 of month.
C
C     Called via:
C        call getday(iyr,jday,imon,idy)
C
C     Assumes:
C        iyr - year (19xx)
C        jday - day number in year (jan 1 is 001)
C
C     Returns:
C        imon - month (1-12)
C        idy - day number

      subroutine getday(iyr,jday,imon,idy)
      iystrt = julday(1,0,iyr)
      do 10 i=1,11
	 imostrt = julday(i+1,1,iyr) - iystrt
	 if (imostrt .gt. jday) go to 15
10    continue
15    continue
      imon = i
      idy = jday + iystrt - julday(imon,0,iyr)
      end
