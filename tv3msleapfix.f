C     Program to fix leap second problem with Taurus systems.  Problem is that
C     for Taurus v3.x systems, if the GPS is not locked when the leap second
C     occurs, all mseed time stamps from midnight when the leap second occurs
C     are wrong.  When the GPS locks, the clock seems to be one second off,
C     causing a time tear.  To fix, change the header times in all mseed
C     blockettes starting with the one crossing of midnight and advancing
C     them by one second up to the time of the time tear.  Program sets
C     activity flag in blockette containing leap second when encountered.
C
C     Command line options:
C        -o <file> - Write repaired time stamps to file provided
C        -e yy mo dy hr mn ss ms - fixing time stamps up to this
C           time.  Leap second is reckoned to be at the preceding 30 June or
C           31 Dec.
C        -s yy mo dy hr mn ss ms - fixing time stamps starting with this
C           time.  Leap second is reckoned to be at the preceding 30 June or
C           31 Dec.
C        -l +1 or -1 - whether leap second is positive (default) or negative.
C        -t - Terse output: no input prompts, no info on what it is doing.
C           Use when you are convinced you understand problem to correct bulk
C           data.
C        -h - Print out usage.
C
C     G. Helffrich/U. Bristol
C         9 Sep. 2013, 5 Feb. 2019
      parameter (iblk=8192,ibmx=iblk-1)
      character buf(0:ibmx), str*(iblk)
      integer data(1000), stim(6), etim(7), dt
      character fn*128, strm*6, pm*2
      equivalence (buf,str)
      logical ohdr, odat, ochr, ok, otrs, ouse, oend
      data ohdr, odat, otrs, ouse/4*.false./, idir/+1/, pm/'-+'/

C     Parse options
      iskip = 0
      do i=1,iargc()
         if (i.le.iskip) cycle
         call getarg(i,fn)
	 if (fn .eq. '-e' .or. fn .eq. '-s') then
	    oend = fn .eq. '-e'
	    do j=1,7
	       call getarg(i+j,fn)
	       if (fn .eq. ' ') stop '**Missing -e value'
	       read(fn,*,iostat=ios) etim(j)
	       if (ios.ne.0) stop '**Bad -s value'
	    enddo
C           Compute nearest occurrence of future leap second.  End time in
C           Jan. means leap second Dec. 31 of previous year.
            if (etim(2) .lt. 7) then
	       stim(1) = etim(1)-1
	       stim(2) = julday(stim(1),12,31) - julday(stim(1),1,0)
	    else
	       stim(1) = etim(1)
	       stim(2) = julday(stim(1),6,30) - julday(stim(1),1,0)
	    endif
	    stim(3) = 23
	    stim(4) = 59
C           Convert end time to yyyy jday hr mn ss ms
	    jday = julday(etim(1),etim(2),etim(3))-julday(etim(1),1,0)
	    etim(2) = jday
	    do j=3,6
	       etim(j) = etim(j+1)
	    enddo
	    iskip = i+7
	    ohdr = .true.
	 else if (fn .eq. '-o') then
	    call getarg(i+1,fn)
	    if (fn.ne.' ')then
	       open(2,file=fn,access='direct',status='new',
     &            recl=iblk,iostat=ios)
               if (ios.ne.0) stop '**Output file exists.'
	       odat = .true.
	    else
	       write(0,*) '**No file name following -o; skipped.'
	    endif
	    iskip = i+1
	 else if (fn .eq. '-l') then
	    call getarg(i+1,fn)
	    if (fn .eq. ' ') stop '**Missing -l value'
	    read(fn,*,iostat=ios) idir
	    if (ios.ne.0 .or. abs(idir).ne.1) stop '**Bad -l value'
	    iskip = i+1
	 else if (fn .eq. '-t') then
	    otrs = .true.
	 else if (fn .eq. '-h') then
	    call usage
	    stop
	 else
	    ix=index(fn,' ')-1
	    write(0,*) '**Unrecognized option: ',fn(1:ix),', skipping.'
	    ouse = .true.
	 endif
      enddo
      if (ouse) call usage

C     Start time depends on direction of leap second
      stim(5) = 59+idir
      stim(6) = 00

      if (.not.odat) stop '**No -o output file given'
      if (.not.ohdr) stop '**No -s/-e time given'
C     print *,'Start: ',(stim(i),i=1,6)
C     print *,'End: ',(etim(i),i=1,6)

C     Get file name
      if (.not.otrs) write(*,*) 'Enter file name:'
      read(*,'(a)',iostat=ios) fn
      if (fn .eq. ' ' .or. ios .ne. 0) stop
      ix = index(fn,' ')-1

C     Open file and read first record, and determine number of multiples
C        of 512 bytes for each 
      ibsz = 256
      do i=1,6
         ibsz = 2*ibsz
	 inquire(1,opened=ok)
	 if (ok) close(1)
         open(1,file=fn,access='direct',form='unformatted',recl=ibsz,
     &      status='old',iostat=ios)
         if (ios .ne. 0) stop '**Invalid file name.'
         read(1,rec=1,iostat=ios) str(1:ibsz)
	 if (ios .ne. 0) stop '**Error on file read (1st rec).'
	 if (buf(6) .ne. 'D') stop '**File is not mseed data.'
	 read(str(1:6),'(i6)',iostat=ios) inum
	 if (ios .ne. 0) stop '**File is not mseed data.'
         read(1,rec=2,iostat=ios) str(1:ibsz)
	 if (ios .ne. 0) stop '**Error on file read (2nd rec).'
	 read(str(1:6),'(i6)',iostat=ios) inxt
	 if (ios .ne. 0 .or.  buf(6) .ne. 'D') cycle
	 if (inum+1 .eq. inxt) exit
      enddo

C     Report station info and block size.
      call mtime(str, irate, iyear, ijday, ihr, imn, isc, ims)
      write(*,*) fn(1:ix),': ',str(9:13),' ',str(14:15),' ',str(16:18),
     &  ' ',str(19:20),irate,' sps, block size ',ibsz 

C     Reopen output file with proper block size
      inquire(2, name=fn)
      close(2)
      open(2,file=fn,access='direct',status='unknown',
     &            recl=ibsz,iostat=ios)
      if (ios.ne.0) stop '**Can''t re-open -o file?!'

C     Read each block and print out information
      nrec = 0
10    continue
         nrec = nrec + 1
         read(1,rec=nrec,iostat=ios) str(1:ibsz)
	 if (ios .ne. 0) go to 99
	 call mtime(str, irate, iyear, ijday, ihr, imn, isc, ims)
	 buft = bufdt(str)
	 is = dt(iyear, ijday, ihr, imn, isc,           stim)
	 ie = dt(iyear, ijday, ihr, imn, isc+int(buft), stim)
	 ileap = 0
	 if (is .ge. 0 .and. oend) then
	    is = dt(iyear, ijday, ihr, imn, isc, etim)
	    if (is .lt. 0 .and. oend) ileap = -idir
	 else if (is .le. 0 .and. ie .ge. 0) then
C           Leap second happened in this blockette.
C           Copy bits 0-3, 6; set bit 4 or 5 depending on + or - leap second
C           to flag leap second occurrence.
	    buf(37) = char(
     &              mod(ichar(buf(37)),16)
     &              + 64*mod(ichar(buf(37))/64,2)
     &              + 16*(1+(1-idir)/2)
     &      )
	 endif
	 if (ileap .eq. 0) then
	    fn = 'unchanged'
	 else
	    ix = 1+max(0,ileap)
	    fn = pm(ix:ix) // '1'
	 endif
	 ix = index(fn,' ')-1
	 if (mod(ichar(buf(37))/16,2).ne.0) then
	    fn(ix+1:) = ' +leap sec. flag$'
	    ix = index(fn,'$')-1
	 endif
	 if (mod(ichar(buf(37))/32,2).ne.0) then
	    fn(ix+1:) = ' -leap sec. flag$'
	    ix = index(fn,'$')-1
	 endif

	 if (.not.otrs) write(*,*) ' Block ',nrec,
     &      ' start ', iyear, ijday, ihr, imn, isc, ims,' -> ',fn(1:ix)
         call inc(ileap, iyear, ijday, ihr, imn, isc, etim(2))
         call mtput(str, irate, iyear, ijday, ihr, imn, isc, ims)
         write(2,rec=nrec,iostat=ios) str(1:ibsz)
	 if (ios.ne.0) stop '**Error on output file write.'
      go to 10

99    continue
      close(2)
      close(1)

      end

      subroutine usage
      write(0,*) 'Usage: tv3msleapfix -o <file>'
      write(0,*) '          -e yy mo dd hh mn ss ms '
      write(0,*) '          [-t | -l {+1 | -1} | -h]...'
      write(0,*) ' where'
      write(0,*) ' -o <file> - output file for repaired blockettes'
      write(0,*) ' -e yy mo dd hh mn ss ms - end time of time tear'
      write(0,*) '    to be repaired by time shift of +1 or -1 sec.'
      write(0,*) ' -s yy mo dd hh mn ss ms - start of time tear'
      write(0,*) '    to be repaired by time shift of +1 or -1 sec.'
      write(0,*) ' -t - terse output; otherwise tells you how each'
      write(0,*) '    blockette time is modified.'
      write(0,*) ' -l +1 or -l -1 - sense of leap second; default +1'
      write(0,*) ' -h - provide usage information (this output)'
      end

      subroutine inc(isec, iyear, ijday, ihr, imn, isc, iljday)
C     INC -- Add a leap second correction to the current time,
C            with carry, accounting for the leap second.
C
C     Assumes:
C        isec - leap second increment (+1 or -1)
C        iyear - year
C        ijday - julian day
C        ihr - hour
C        imn - minute
C        isc - second
C        iljday - leap second julian day (182/183 or 365/366 depending on leap
C           year)
C
C     Returns:
C        iyear, ijday, ihr, imn, isc - corrected as for leap second increment.

      logical carry

      isc = isc + isec
      carry = .false.
      if (ihr .eq. 23 .and. imn .eq. 59 .and. ijday .ne. iljday) then
        if (isc.gt.59+isec) carry = .true.
      else
        carry = isc.gt.59
      endif
      if (carry) then
	 isc = 0
	 imn = imn + 1
	 if (imn .gt. 59) then
	    imn = 0
	    ihr = ihr + 1
	    if (ihr .gt. 23) then
	       ihr = 0
	       ijday = ijday + 1
	       ieoyr = julday(iyear,12,31) - julday(iyear,1,0)
	       if (ijday .gt. ieoyr) then
	          ijday = 1
		  iyear = iyear + 1
	       endif
	    endif
	 endif
      endif
      end

      integer function dt(iyear, ijday, ihr, imn, isc, etim)
C     DT -- Return time difference in seconds between dates
C           Because we are only interested in the lapse between a time
C           either beginning or ending on a leap second, the number
C           of seconds in a day will always be 86,400 -- no leap second
C           will happen in any interval of interest.
C
C     Assumes:
C        iyear - year
C        ijday - julian day
C        ihr - hour
C        imn - minute
C        isc - second
C        etim - array of integer values: year, jday, hour, min, sec
      integer etim(5)

      dt = 86400*(julday(iyear,1,ijday) - julday(etim(1),1,etim(2)))
      dt = dt + 3600*(ihr-etim(3))
      dt = dt + 60*(imn-etim(4))
      dt = dt + (isc-etim(5))
      end

*struct _btime_ {
*       unsigned short  0 year;
*       unsigned short  2 jday;
*       unsigned char   4 hour;
*       unsigned char   5 min;
*       unsigned char   6 sec;
*       unsigned char   7 unused;
*       unsigned short  8 cns;
*};

*typedef struct _btime_ BTIME;

*struct  _drh_ {
*        char            0 recnum[6];
*        char            6 rectype;
*        char            7 reserved;
*        char            8 stat[5];
*        char           13 locid[2];
*        char           15 chan[3];
*        char           18 net[2];
*        BTIME          20 btime;
*        unsigned short 30 nsamp;
*        short          32 srf;
*        short          34 srm;
*        char           36 aflg;
*        char           37 iflg;
*        char           38 qflg;
*        unsigned char  39 nofb;
*        int            40 tc;
*        unsigned short 44 bod;
*        unsigned short 46 fb;
*};

C     MTPUT -- Routine to modify time of first sample in MSEED blockette.
C
C     Assumes:
C        buf - character array containing data block.
C        sr - sample rate
C        year - integer year
C        jday - integer julian day in year (1-366)
C        hr - integer hour
C        mn - integer minute
C        sc - integer second
C        ms - integer millisecond
C
C     Returns:
C        buf - modified with values for year, jday, hr, mn, sc, ms

      subroutine mtput(buf, sr, year, jday, hr, mn, sc, ms)
      character buf*64
      integer word, year, jday, hr, mn, sc, ms, sr
      integer*2 ihalf
      character chalf(2), cwhol*2
      equivalence (ihalf,chalf,cwhol)

      cwhol = buf(23:24)
      if (ihalf .ge. 1 .and. ihalf .le. 366) then
         ihalf = year
	 buf(21:22) = cwhol(1:2)
	 ihalf = jday
	 buf(23:24) = cwhol(1:2)
	 ihalf = ms
	 buf(29:30) = cwhol(1:2)
      else
         ihalf = year
	 buf(21:21) = chalf(2)
	 buf(22:22) = chalf(1)
	 ihalf = jday
	 buf(23:23) = chalf(2)
	 buf(24:24) = chalf(1)
	 ihalf = ms
	 buf(29:29) = chalf(2)
	 buf(30:30) = chalf(1)
      endif
      buf(25:25) = char(hr)
      buf(26:26) = char(mn)
      buf(27:27) = char(sc)
      end

C     MTIME -- Routine to return time of first sample in MSEED blockette.
C
C     Assumes:
C        buf - character array containing data block
C
C     Returns:
C        sr - sample rate (samples/second)
C        year - integer year
C        jday - integer julian day in year (1-366)
C        hr - integer hour
C        mn - integer minute
C        sc - integer second
C        ms - integer milliseconds

      subroutine mtime(buf, sr, year, jday, hr, mn, sc, ms)
      character buf*64
      integer year, jday, hr, mn, sc, ms, sr, srf, srm
      integer*2 ihalf
      character chalf(2), cwhol*2, btime*10
      equivalence (ihalf,chalf,cwhol)

      btime = buf(21:30)
      cwhol = btime(3:4)
      if (ihalf .ge. 1 .and. ihalf .le. 366) then
         jday = ihalf
         cwhol = btime(1:2)
         year = ihalf
         cwhol = btime(9:10)
         ms = ihalf
         cwhol = buf(33:34)
         srf = ihalf
         cwhol = buf(35:36)
         srm = ihalf
      else
         chalf(1) = btime(2:2)
         chalf(2) = btime(1:1)
         year = ihalf
         chalf(1) = btime(4:4)
         chalf(2) = btime(3:3)
         jday = ihalf
         chalf(1) = btime(10:10)
         chalf(2) = btime(9:9)
         ms = ihalf
         chalf(1) = buf(34:34)
         chalf(2) = buf(33:33)
         srf = ihalf
         chalf(1) = buf(36:36)
         chalf(2) = buf(35:35)
         srm = ihalf
      endif
      hr = ichar(btime(5:5))
      mn = ichar(btime(6:6))
      sc = ichar(btime(7:7))
      if (srf.gt.0)then
         if (srm.gt.0) then
            sr = srf*srm
         else
            sr = nint(srf/(0.-srm))
         endif
      else
         if (srm.lt.0) then
            sr = nint(1/((0.-srf)*srm))
         else
            sr = nint(float(srm)/srf)
         endif
      endif
      end

C     BUFDT -- Routine to return time contained in an MSEED blockette.
C
C     Assumes:
C        buf - character array containing data block
C
C     Returns:
C        Function result - number of seconds of data in buffer.

      function bufdt(buf)
      character buf*64
      integer srf, srm
      integer*2 ihalf
      character chalf(2), cwhol*2, btime*10
      equivalence (ihalf,chalf,cwhol)

      btime = buf(21:30)
      cwhol = btime(1:2)
      if (ihalf .ge. 1900 .and. ihalf .le. 2500) then
         cwhol = buf(33:34)
         srf = ihalf
         cwhol = buf(35:36)
         srm = ihalf
	 cwhol = buf(31:32)
	 npts = ihalf
      else
         chalf(1) = buf(34:34)
         chalf(2) = buf(33:33)
         srf = ihalf
         chalf(1) = buf(36:36)
         chalf(2) = buf(35:35)
         srm = ihalf
	 chalf(1) = buf(32:32)
	 chalf(2) = buf(31:31)
	 npts = ihalf
      endif
      if (srf.gt.0)then
         if (srm.gt.0) then
            sr = srf*srm
         else
            sr = srf/(0.-srm)
         endif
      else
         if (srm.lt.0) then
            sr = 1/((0.-srf)*srm)
         else
            sr = float(srm)/srf
         endif
      endif
      bufdt = npts/sr
      end

      FUNCTION JULDAY(IYYY,MM,ID)
      PARAMETER (IGREG=15+31*(10+12*1582))
      IF (IYYY.EQ.0) PAUSE '**JULDAY:  There is no Year Zero.'
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
