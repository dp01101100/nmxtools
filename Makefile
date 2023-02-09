PREFIX = /usr/local
LIBDIR = $(PREFIX)/lib
BINDIR = $(PREFIX)/bin
SACLIB = /usr/local/lib/geophy/sac.a
FFLAGS = -g -fbounds-check
CFLAGS = -g
FC = gfortran

EXEC = rnmseed splitseed mseedtime masspos tv2mseed tv3mseed tv3msleapfix \
	dumpv2 dumpv3

rnmseed: rnmseed.o julday.o
	$(FC) ${FFLAGS} -o rnmseed rnmseed.o julday.o

mseedtime: mseedtime.o julday.o
	$(FC) ${FFLAGS} -o mseedtime mseedtime.o julday.o

mseedsort: mseedsort.o julday.o
	$(FC) ${FFLAGS} -o mseedsort mseedsort.o julday.o

splitseed: splitseed.o julday.o
	$(FC) ${FFLAGS} -o splitseed splitseed.o julday.o

masspos: masspos.o julday.o
	$(FC) ${FFLAGS} -o masspos masspos.o julday.o ${SACLIB}

tv2mseed: tv2mseed.o
	$(CC) ${CFLAGS} -o tv2mseed tv2mseed.o

tv2msleapfix: tv2msleapfix.o
	$(FC) ${FFLAGS} -o tv2msleapfix tv2msleapfix.o

tv3mseed: tv3mseed.o
	$(CC) ${CFLAGS} -o tv3mseed tv3mseed.o

tv3msleapfix: tv3msleapfix.o
	$(FC) ${FFLAGS} -o tv3msleapfix tv3msleapfix.o

dumpv2: dumpv2.o
	$(CC) ${CFLAGS} -o dumpv2 dumpv2.o

dumpv3: dumpv3.o
	$(CC) ${CFLAGS} -o dumpv3 dumpv3.o

install: mseedtime masspos
	install -c -m 644 leapseconds $(LIBDIR)
	install mseedtime $(BINDIR)

clean:
	/bin/rm -f *.o core
	/bin/rm -rf *.dSYM

distclean: clean
	/bin/rm -f ${EXEC}

dist: distclean
	/bin/rm -f /tmp/taurussrc.tgz
	(cd ..; tar cfz /tmp/taurussrc.tgz taurussrc)
	echo "Source distribution in /tmp/taurussrc.tgz"
