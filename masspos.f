      program masspos
      parameter (nmax=2**16)
      double precision t0, tn
      character arg*64, ymd*16, hms*16, ofile*64, sta*5, cmp*8
      real t(nmax), pos(nmax)

      ofile = ' '
      ymd = ' '
      hms = ' '
      sta = ' '
      cmp = ' '
      iskip = 0
      do i=1,iargc()
         if (i .le. iskip) cycle 
	 call getarg(i,arg)
	 if (arg .eq. '-time') then
	    iskip = i+2
	    call getarg(i+1,ymd)
	    call getarg(i+2,hms)
	    do j=1,nblen(ymd)
	       if (index('0123456789',ymd(j:j)) .eq. 0) ymd(j:j) = ' '
	    enddo
	    read(ymd,*,iostat=ios) iyr,imo,idy
	    if (ios.ne.0) stop '**Bad date format'
	    do j=1,nblen(hms)
	       if (index('0123456789',hms(j:j)) .eq. 0) hms(j:j) = ' '
	    enddo
	    read(hms,*,iostat=ios) ihh,imm,iss
	    if (ios.ne.0) stop '**Bad date format'
	    jday = julday(imo,idy,iyr) - julday(1,0,iyr)
	 else if (arg .eq. '-o') then
	    iskip = i+1
	    call getarg(i+1,ofile)
	 else if (arg(1:2) .eq. '-c') then
	    iskip = i+1
	    call getarg(i+1,cmp)
	 else if (arg(1:4) .eq. '-sta') then
	    iskip = i+1
	    call getarg(i+1,sta)
	 else
	    write(0,*) '**Unrecognized parameter: ',arg(1:nblen(arg)),
     &         ', skipping.'
         endif
      enddo

      if (ofile .eq. ' ') stop '**No output file given (-o xxxx)'
      if (ymd .eq. ' ' .or. hms .eq. ' ') then
         stop '**No start time given (-time yyyy/mm/dd hh:mm:ss)'
      endif

1000  format('**Bad input format:  line ',i5)

      n = 0
      npts = 0
      do
         read(*,'(a)',iostat=ios) arg
	 if (ios .ne. 0) exit
	 n = n + 1
	 ib = 0
	 ie = 0
	 ix = nblen(arg)
	 do i=0,ix-1
	    if = 1+i
	    ir = ix-i
	    if (arg(if:if) .eq. ' ' .and. ib.eq.0) ib=if-1
	    if (arg(ir:ir) .eq. ' ' .and. ie.eq.0) ie=ir+1
	    if (ib .ne. 0 .and. ie .ne. 0) exit
	 enddo

	 if (ib.eq.0 .or. ie.eq.0) then
	    write(0,1000) n
	    cycle
	 endif

	 if (n .eq. 1) then
	    read(arg(1:ib),*,iostat=ios) t0
	    if (ios.ne.0) then
	       write(0,1000) n
	       stop
	    endif
	 endif

	 read(arg(1:ib),*,iostat=ios1) tn
	 read(arg(ie:ix),*,iostat=ios2) pn
	 if (ios1.ne.0 .or. ios2.ne.0) then
	    write(0,1000) n
	    cycle
	 endif
	 npts = npts + 1
	 t(npts) = real(tn-t0)
	 pos(npts) = pn
      enddo

      call newhdr
      call setnhv('nzyear',iyr,nerr)
      call setnhv('nzjday',jday,nerr)
      call setnhv('nzhour',ihh,nerr)
      call setnhv('nzmin',imm,nerr)
      call setnhv('nzsec',iss,nerr)
      call setnhv('nzmsec',0,nerr)
      call setihv('iftype','ixy',nerr)
      call setihv('idep','ivolts',nerr)
      call setlhv('leven',.false.,nerr)
      call setnhv('npts',npts,nerr)
      if (sta .ne. ' ') call setkhv('kstnm',sta,nerr)
      if (cmp .ne. ' ') call setkhv('kcmpnm',cmp,nerr)
      call wsac0(ofile,t,pos,nerr)
      if (nerr .ne. 0)
     &   write(0,*) '**Trouble writing ',ofile(1:nblen(ofile))
      end


      function nblen(str)
      character str*(*)

      do i=len(str),1,-1
         if (str(i:i) .ne. ' ') exit
      enddo
      nblen = i
      end
