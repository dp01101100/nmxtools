C     Program to read first data blockette of a a Nanometrics MSEED file
C     and write out the original and the revised file name for use with the
C     GEOFON program suite.  Optionally will build a mv command to rename
C     files which undergo name changes.
C
C     As command line argument, give MSEED file name.  Output is start time.
C     Otherwise, reads file names from std. input and processes each one.
C     Options:
C        -b - block size in bytes [default 512]
C        -mv - write output as mv commands for renaming (as shell
C           script input)
C        -new - create entirely new name from station info in header.
C           Otherwise, the file name is searched for a string that
C           contains YYMMDD000000 (year, month day) of the first datum
C           and replaces the 000000 with the HHMMSS of the first sample.
C        -noseq - ignore out-of-sequence block numbering.
C
C     By George Helffrich, U. Bristol, June 1, 2007, Oct. 10, 2010
C        updated 26 May 2014
      program rnmseed
      parameter (mxbuf=8192, iucd=99)
      character posstr*16
      character cdname*256, fn*256, sname*32, posn*16
      character inbuf*(mxbuf)
      integer lrecl
      logical omv,onew,oseq

      omv = .false.
      onew = .false.
      oseq = .true.
      lrecl = 512
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
	    else if (posn .eq. '-mv') then
	       omv = .true.
	    else if (posn .eq. '-new') then
	       onew = .true.
	    else if (posn .eq. '-noseq') then
	       oseq = .false.
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

	 nprec = 1
	 read(iucd, rec=nprec, err=9100) inbuf(1:lrecl)
	 read(inbuf(1:6),*,iostat=ios) nrec
	 if (ios .ne. 0 .or. nrec .ne. nprec) then
	    if (nprec .eq. 1) then
	       write(0,*) '**Read error: blocks out of sequence.'
	       write(0,*) '**Expecting ',nprec,' but got ',inbuf(1:6),
     &           '.'
            endif
	    if (oseq) go to 9000
	 endif
	 if (0 .eq. index('DRQM',inbuf(7:7))) then
	    write(0,*) '**Read error: block ',nprec,
     &         ' is not data block, but is labeled ',inbuf(7:7),'.'
	    go to 9000
	 endif
C        Decode time.
         call tmdec(inbuf(21:30),iyr,ijd,ihr,imn,isc,ith)
         call getday(iyr,ijd,imo,idd)
C        write(sname,'(i4.4,i2.2,i2.2,i2.2,i2.2,i2.2,i4.4)')
C    &      iyr,imo,idd,ihr,imn,isc,ith
         write(sname,'(i2.2,i2.2,i2.2,i2.2,i2.2,i2.2)')
     &      mod(iyr,100),imo,idd,ihr,imn,isc
         if (onew) then
	    ix = indexr(cdname,'/')
	    if (ix.gt.0) then
	       fn(1:ix) = cdname(1:ix)
	       ix = ix+1
	    else
	       ix = 1
	    endif
	    iy = index(inbuf(9:13),' ')
	    if (iy.eq.0) then
	       iy = 13
	    else
	       iy = 7+iy
	    endif
1001        format(a,a,'.',a)
	    write(fn(ix:),1001) inbuf(9:iy),sname(1:12),inbuf(16:18)
	 else
	    fn = cdname
	    ix = index(cdname,sname(1:6))
	    if (ix .ne. 0) then
	       if (cdname(ix+6:ix+11) .eq. '000000') then
		  fn(ix+6:ix+11) = sname(7:12)
	       endif
	    endif
	 endif
	 ix = index(cdname, ' ')
	 iy = index(fn, ' ')
	 if (omv .and. cdname(1:ix-1).ne.fn(1:iy-1)) then
	    write(*,'(a,1x,a,1x,a)') 'mv',cdname(1:ix-1),fn(1:iy-1)
	 else if (.not.omv) then
	    write(*,'(a,1x,a)') cdname(1:ix-1),fn(1:iy-1)
	 endif
9000     continue
         close(iucd)
         if (n .ne. 0) stop
      go to 1000
9100  continue
      write(0,*) '**Read error on input file.'
      end

      subroutine tmdec(btime,iyr,ijd,ihr,imn,isc,ith)
      character btime*10

      integer ihalf*2
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

      function indexr(str,chr)
      character str*(*), chr*1

      do i=len(str),1,-1
         if (str(i:i) .eq. chr) exit
      enddo
      indexr=i
      end
