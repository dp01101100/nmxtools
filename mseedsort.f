C     Program to read data blockettes of a Nanometrics MSEED file
C     and write out the information for the station, locid, channel, block,
C     and start time of the first sample in each blockette.
C
C     As command line argument, give MSEED file name.
C     Options:
C       -b # - block size in bytes [default 512]
C       -o <file> - untangle blocks and write to <file>;
C          std input is a list of block numbers to write
C
C     By George Helffrich, U. Bristol, July 14, 2011
C        last update Jan. 31, 2019
      program rnmseed
      parameter (mxbuf=8192, iucd=99, iuof=98)
      character posstr*16
      character cdname*256, fn*256, sname*32, posn*16
      character inbuf*(mxbuf), locid*2, netwk*2
      integer lrecl
      logical olst, owrt, oquiet

      olst = .true.
      owrt = .false.
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
	    else if (posn .eq. '-o') then
	       call getarg(i+1,fn)
	       iskip = i+1
	       olst = .false.
	       owrt = .true.
	    else if (posn .eq. '-q') then
	       oquiet = .true.
	    else if (posn .eq. '-h') then
	       call getarg(0,sname)
	       ix = index(sname,' ')-1
	       write(0,*) ' usage:  ',sname(1:ix),' [options] file'
	       write(0,*) ' -b <size> - block size (512 default)'
	       write(0,*) ' -o <file> - rewrite file in sort order'
	       write(0,*) '      stdin gives record # rewrite order'
	       write(0,*) ' -q - don''t complain about record # order'
	       write(0,*) ' -h - help (this output)'
	    else
	       write(0,*) '**Bad option: ',posn(1:index(posn,' ')-1)
	       stop
	    endif
	 else
            if (n .eq. 0) call getarg(i,cdname)
	    n = n + 1
	 endif
5     continue

      if (n .eq. 0) stop '**No input file name given.'
      open(iucd,file=cdname,
     &      access='direct',
     &      form='unformatted',
     &      recl=lrecl,
     &      iostat=ios)
      if (ios .ne. 0) stop '**Bad file name, can''t open.'

      if (owrt) then
         open(iuof,file=fn,
     &      access='direct',
     &      form='unformatted',
     &      recl=lrecl,
     &      iostat=ios)
         if (ios .ne. 0) stop '**Bad output file name, can''t write.'
      endif

1000  continue
         if (olst) then
	    read(iucd, rec=nprec, err=9100) inbuf(1:lrecl)
	    read(inbuf(1:6),*,iostat=ios) nrec
	    if (.not.oquiet .and.
     &         (ios .ne. 0 .or. nrec .ne. mod(nprec,1 000 000))
     &      ) then
	       write(0,*) '**Read error: blocks out of sequence.'
	       write(0,*) '**Expecting ',nprec,' but got ',inbuf(1:6),'.'
	    endif
	    if (0.eq.index('DRMQ',inbuf(7:7))) then
	       write(0,*) '**Read error: block ',nprec,
     &            ' is not data block, but is ',inbuf(7:7),'.'
	       go to 9100
	    endif
C           Decode time.
            call tmdec(inbuf(21:30),iyr,ijd,ihr,imn,isc,ith)
            call getday(iyr,ijd,imo,idd)
            write(sname,'(i4.4,1x,i2.2,1x,i2.2,1x,i2.2,1x,i2.2,1x,i2.2,
     &         1x,i4.4)') iyr,imo,idd,ihr,imn,isc,ith
C           Decode location
            locid = inbuf(14:15)
	    if (locid .eq. ' ') locid = '--'
            netwk = inbuf(19:20)
	    if (netwk .eq. ' ') netwk = '--'
	    write(*,'(a,1x,a,1x,a,1x,a,1x,i6,1x,a)')
     &         inbuf(9:13),locid,inbuf(16:18),netwk,nprec,sname
	 else
	    read(*,*,iostat=ios) nrec
	    if (ios .ne. 0) then
	       close(iuof)
	       close(iucd)
	       stop
	    endif
	    read(iucd, rec=nrec, err=9300) inbuf(1:lrecl)
	    if (0.eq.index('DRMQ',inbuf(7:7))) then
	       write(0,*) '**Read error: block ',nrec,
     &            ' is not data block, but is ',inbuf(7:7),'.'
	       go to 9100
	    endif
	    write(inbuf(1:6),'(i6.6)') mod(nprec,1 000 000)
	    write(iuof, rec=nprec, err=9200) inbuf(1:lrecl)
	 endif
	 nprec = nprec + 1
      go to 1000

9000  continue
      stop

9100  continue
      if (nprec.le.1) write(0,*) '**Read error on input file.'
      close(iucd)
      stop

9200  continue
      write(0,*) '**Write error on output file, record ',nprec
      close(iuof)
      stop

9300  continue
      write(0,*) '**Read error on copy file, record ',nrec
      close(iuof)
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
