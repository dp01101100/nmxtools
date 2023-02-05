C     Program to read first data blockette of a a Nanometrics MSEED file
C     and write out the information for the station, locid, channel and start
C     time of the first sample in the file.
C
C     As command line argument, give MSEED file name.  Output is start time.
C     Options:  -b - block size in bytes [default 512]
C        -# <num> - read record num [default 1]
C        -r - if record num does not match sequence #, read anyway
C        -q - don't check or complain aobout record mismatch (implies -r)
C
C     By George Helffrich, U. Bristol, Nov. 10, 2007
C        updated 31 Jan. 2019.
      program rnmseed
      parameter (mxbuf=8192, iucd=99)
      character posstr*16
      character cdname*256, fn*256, sname*32, posn*16
      character inbuf*(mxbuf), locid*2, netwk*2
      integer lrecl
      logical orec, oquiet

      orec = .false.
      oquiet = .false.
      lrecl = 512
      nprec = 1
      n = 0
      iskip = 0
      do 5 i=1,iargc()
	 if (i .le. iskip) go to 5
	 call getarg(i,posn)
	 if (posn(1:1) .eq. '-') then
	    if (posn .eq. '-b') then
	       call getarg(i+1,posn)
	       ios = -1
	       if (posn .ne. ' ') read(posn,*,iostat=ios) lrecl
	       if (ios .ne. 0) stop '**Bad -b value'
	       if (lrecl .gt. mxbuf) stop '**-b value too large'
	       iskip = i+1
	    else if (posn .eq. '-#') then
	       call getarg(i+1,posn)
	       ios = -1
	       if (posn .ne. ' ') read(posn,*,iostat=ios) nprec
	       if (ios .ne. 0) stop '**Bad -# value'
	       iskip = i+1
	    else if (posn .eq. '-r') then
	       orec = .true.
	    else if (posn .eq. '-q') then
	       oquiet = .true.
	    else
	       write(0,*) '**Bad option: ',posn(1:index(posn,' ')-1)
	       stop
	    endif
	 else
            if (n .eq. 0) call getarg(i,cdname)
	    n = n + 1
	 endif
5     continue

1000  continue
         if (n .le. 0) then
	    read(*,'(a)',iostat=ios) cdname
	    if (ios.ne.0) stop
	 endif

         open(iucd,file=cdname,
     &      access='direct',
     &      form='unformatted',
     &      recl=lrecl,
     &      iostat=ios)
         if (ios .ne. 0) stop '**Bad file name, can''t open.'

	 read(iucd, rec=nprec, err=9100) inbuf(1:lrecl)
	 read(inbuf(1:6),*,iostat=ios) nrec
	 if (ios .ne. 0 .or.
     &      (.not.oquiet .and. nrec .ne. nprec)
     &   ) then
	    write(0,*) '**Read error: blocks out of sequence.'
	    write(0,*) '**Expecting ',nprec,' but got ',inbuf(1:6),'.'
	    if (.not.orec) go to 9000
	 endif
	 if (0 .eq. index('DRMQ',inbuf(7:7))) then
	    write(0,*) '**Read error: block ',nprec,
     &         ' is not data block, but is ',inbuf(7:7),'.'
	    go to 9000
	 endif
C        Decode time.
         call tmdec(inbuf(21:30),iyr,ijd,ihr,imn,isc,ith)
         call getday(iyr,ijd,imo,idd)
         write(sname,'(i4.4,1x,i2.2,1x,i2.2,1x,i2.2,1x,i2.2,1x,i2.2,
     &      1x,i4.4)') iyr,imo,idd,ihr,imn,isc,ith
C        Decode location
         locid = inbuf(14:15)
	 if (locid .eq. ' ') locid = '--'
         netwk = inbuf(19:20)
	 if (netwk .eq. ' ') netwk = '--'
	 write(*,'(a,1x,a,1x,a,1x,a,1x,a)')
     &      inbuf(9:13),locid,inbuf(16:18),netwk,sname
9000     continue
         close(iucd)
         if (n .ne. 0) stop
      go to 1000
9100  continue
      write(0,*) '**Read error on input file.'
      end

      subroutine tmdec(btime,iyr,ijd,ihr,imn,isc,ith)
      character btime*10

      integer*2 ihalf
      character chalf*2
      equivalence (ihalf, chalf)

      chalf = btime(1:2)
      if (ihalf .ge. 1900 .and. ihalf .le. 2500) then
	 iyr = ihalf
	 chalf = btime(3:4)
	 ijd = ihalf
	 chalf = btime(9:10)
      else
	 chalf(1:1) = btime(2:2)
	 chalf(2:2) = btime(1:1)
	 iyr = ihalf
	 chalf(1:1) = btime(4:4)
	 chalf(2:2) = btime(3:3)
	 ijd = ihalf
	 chalf(1:1) = btime(10:10)
	 chalf(2:2) = btime(9:9)
      endif
      ihr = ichar(btime(5:5))
      imn = ichar(btime(6:6))
      isc = ichar(btime(7:7))
      ith = ihalf
      end
