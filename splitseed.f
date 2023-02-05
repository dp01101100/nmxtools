C     Program to scan a Nanometrics SEED file comprised of data blockettes
C     and split out into separate mseed files based on stream identification.
C
C     As command line argument, give SEED file path name and mseed
C     output stream prefix.
C     Options:  -s n[hd] - split blockettes into separate files at n hour or
C                  day boundaries
C               -b - block size in bytes [default 512]
C               -d xxx - put data into directory xxx [default .]
C               -S nnnn - change station name to nnnn
C               -N XX - change network code to XX
C               -L XX - only select data with LOCID XX
C               -i - ignore sequence checking
C
C     By George Helffrich, U. Bristol, June 3-4, 2006
C        updated 2 Sep. 2014
C        updated 24 Feb. 2022
      program splitseed
      parameter (mxbuf=8192, istmx=8, iucd=99)
      character posstr*16
      character cdname*256, fn*256, dname*64, nsta*5, nnet*2, lid*2
      character inbuf*(mxbuf), strm(istmx)*10, sname*18
      integer lrecl, hmul, rec(istmx), hnow(istmx)
      logical osta, onet, oign
      character posn*16
      data osta, onet, oign /3*.false./, lid/'  '/

      cdname = ' '
      dname = '.'
      hmul = 1
      lrecl = 512
      n = 0
      iskip = 0
      do 5 i=1,iargc()
	 if (i .le. iskip) go to 5
	 call getarg(i,posn)
	 if (posn(1:1) .eq. '-') then
	    if (posn .eq. '-d') then
	       call getarg(i+1, dname)
	       iskip = i+1
	    else if (posn .eq. '-b') then
	       call getarg(i+1,posn)
	       ios = -1
	       if (posn .ne. ' ') read(posn,*,iostat=ios) lrecl
	       if (ios .ne. 0) stop '**Bad -b value'
	       if (lrecl .gt. mxbuf) stop '**-b value too large'
	       iskip = i+1
	    else if (posn .eq. '-s') then
	       call getarg(i+1,posn)
	       ix = index(posn,' ')-1
	       if (ix.lt.1) stop '**Loooong -s value'
	       if (0 .eq. index('dh',posn(ix:ix)))
     &            stop '**Bad -s scale factor'
	       ios = -1
	       if (posn .ne. ' ') read(posn(:ix-1),*,iostat=ios) hmul
	       if (ios .ne. 0) stop '**Bad -s value'
	       if (posn(ix:ix) .eq. 'd') hmul = hmul*24
	       iskip = i+1
	    else if (posn .eq. '-S') then
	       call getarg(i+1,nsta)
	       osta = nsta .ne. ' '
	       iskip = i+1
	    else if (posn .eq. '-N') then
	       call getarg(i+1,nnet)
	       onet = nnet .ne. ' '
	       iskip = i+1
	    else if (posn .eq. '-L') then
	       call getarg(i+1,lid)
	       iskip = i+1
	    else if (posn .eq. '-i') then
	       oign = .true.
	    else
	       write(0,*) '**Bad option: ',posn(1:index(posn,' ')-1)
	       stop
	    endif
	 else
            if (n .eq. 0) call getarg(i,cdname)
	    n = n + 1
	 endif
5     continue
      if (cdname .eq. ' ') stop '**No CD or file provided.'
      ixd = index(dname,' ')-1
      if (ixd .lt. 0) ixd = len(dname)

      open(iucd,file=cdname,
     &   access='direct',
     &   form='unformatted',
     &   recl=lrecl,
     &   iostat=ios)
      if (ios .ne. 0) stop '**Bad file name, can''t open.'
      istrm = 0

      nprec = 1
10    continue
	 read(iucd, rec=nprec, err=9100) inbuf(1:lrecl)
	 read(inbuf(1:6),*,iostat=ios) nrec
	 if (ios .ne. 0 .or. nrec .ne. mod(nprec,1 000 000)) then
	    if (.not. oign) then
	       write(0,*) '**Read error: blocks out of sequence.'
	       write(0,*) '**Expecting ',nprec,' but got ',inbuf(1:6),'.'
	       go to 9000
	    endif
	 endif
	 if (0 .eq. index('DRMQ',inbuf(7:7))) then
	    write(0,*) '**Read error: block ',nprec,
     &         ' is not data block, but is ',inbuf(7:7),'.'
	    go to 9000
	 endif
	 if (lid .ne. '  ') then
	    if (inbuf(14:15) .ne. lid) then
	       nprec = nprec + 1
	       go to 10
	    endif
	 endif
C        Decode time.
         call tmdec(inbuf(21:30),iyr,ijd,ihr,imn,isc,ith)
C        Check if a new stream
         do is=1,istrm
	    if (inbuf(9:18) .eq. strm(is)) then
	       if (hnow(is) .ne. (24*(ijd-1)+ihr)/hmul) then
	          close(10+is)
		  go to 1000
	       endif
	       go to 1100
	    endif
	 enddo
C        New stream.  Name file.
	 istrm = istrm + 1
	 strm(istrm) = inbuf(9:19)

1000     continue
         call getday(iyr,ijd,imo,idd)
C        write(sname,'(i4.4,i2.2,i2.2,i2.2,i2.2,i2.2,i4.4)')
C    &      iyr,imo,idd,ihr,imn,isc,ith
         write(sname,'(i2.2,i2.2,i2.2,i2.2,i2.2,i2.2)')
     &      mod(iyr,100),imo,idd,ihr,imn,isc
         if (osta) inbuf(9:13) = nsta
         if (onet) inbuf(14:15) = nnet
C        if (sname(15:16) .eq. '00') then
C           iy = 14
C        else
C           iy = 16
C        endif
         iy = 12
         ix = index(inbuf(9:15),' ')
	 if (ix .eq. 0) then
	    ix = 15
	 else
	    ix = 9+ix-2
	 endif
	 if(0.ne.index(sname(1:iy),'*'))then
	    write(0,'(a,1x,a,1x,z8.8)') 'file name error at :',
     &         inbuf(1:6),nprec
	    write(0,*) 'file name error: ',iyr,imo,idd,ihr,imn,isc,ith
	 endif
	 fn = dname(1:ixd) // '/' //
     &      inbuf(9:ix) // sname(1:iy) // '.' // inbuf(16:18)
	 open(10+is,
     &      file=fn,
     &      recl=lrecl,
     &      access='direct',
     &      form='unformatted',
     &      iostat=ios)
	 if (ios .ne. 0) then
	    write(0,*) '**Unable to open ',fn(1:index(fn,' ')),'oh oh.'
	    go to 9000
	 endif
	 rec(istrm) = 0
	 hnow(istrm) = (24*(ijd-1)+ihr)/hmul

1100     continue
         rec(is) = rec(is) + 1
	 write(inbuf(1:6),'(i6.6)') rec(is)
         if (osta) inbuf(9:13) = nsta
         if (onet) inbuf(14:15) = nnet
	 write(10+is,
     &      rec=rec(is),
     &      iostat=ios) inbuf(1:lrecl)
	 if (ios .ne. 0) then
	    write(0,*) '**Unable to write ',fn(1:index(fn,' ')),
     &      ' record ',rec(is),'.'
	    go to 9000
	 endif

	 nprec = nprec + 1
      go to 10

9100  continue
      write(*,*) nprec-1,' blocks read.'

9000  continue
      close(iucd)
      do i=1,istrm
	 close(10+i)
      enddo
      end

      subroutine tmdec(btime,iyr,ijd,ihr,imn,isc,ith)
      character btime*10

      integer*2 ihalf
      character chalf*2
      equivalence (ihalf, chalf)

      chalf = btime(1:2)
      if (ihalf .gt. 1900 .and. ihalf .le. 2500) then
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
