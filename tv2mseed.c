/* Decode data packets in Taurus v2 store files and dump as mseed blockettes.

   G. Helffrich/U. Bristol
   original v2 31 Aug. 2012 (cloned from v3 store reader)
   last mod 8 Sep. 2013
            5 Feb. 2023
            9 Feb. 2023
           11 Feb. 2023
           17 Feb. 2023

Usage:  tv2mseed {-v | -z <file> | -n <file> | -e <file> |
                  -l [+|-] [jun|dec] <year>} ... <store>

Command line parameters:
   -h - usage (this text)
   -v - verbose output (repeat for more verbosity)
   -z <file> - Dump MSEED blockettes for Z component to named file
   -n <file> - Dump MSEED blockettes for N component to named file
   -e <file> - Dump MSEED blockettes for E component to named file
   -S <name> - Explicitly set station name
   -N <name> - Explicitly set network ID
   -soh <file> - Dump SOH detail in named file.
   -sohdt <sec> - SOH sampling is every <sec> seconds (default 60).
   -item {T|Z|N|E|V|P} - SOH item to dump.  Encoding:
      T - temperature in logger (C)
      V - power supply voltage (mV)
      P - position (lat N, lon E, elev m) [text-only option]
      Z, N, E - mass position (V)
   -fmt {text|mseed} - SOH dump format; one is human-readable, the other is
      a time series of MSEED data packets.
   -l [+|-] [jun|dec] <year> - Describe leap second in store time
      span.  Data in blockettes spanning the leap second will be
      flagged appropriately in the Activity field of the blockette so that
      time stamps may be reckoned correctly.  Sign of leap second, month
      and year of application must be specified, e.g.
         -l + jun 2012
      describes the June 2012 leap second (positive).
   <store> - store file to search.  This should be the first store file in
      the group describing a store, and a name that includes the suffix
      "001.store"  The rest of the store's file names are derived from this.

   Data packets and requested SOH packets are extracted and converted to MSEED.
   Any packets not associated with a file to receive them are skipped.  Thus it
   is possible to retrieve any or all components of data with a single pass
   through the store.

   SOH sample rate is variable; depends on Taurus configuration.  Inferred from
   timing of SOH information.

*/

#include <unistd.h>
#include <stdlib.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <math.h>
#include <time.h>

#define HDRSIZ 36

char *prog;

short verb = 0, lpsc = 0;

char snam[5], snet[2];

enum soh_info {
   SOH_UNASSIGNED,
   SOH_POS = 'P',
   SOH_TEMP = 'I',
   SOH_MASS1_V = 'Z',
   SOH_MASS2_V = 'N',
   SOH_MASS3_V = 'E',
   SOH_SUPPLY_V = 'V'
} soh_itm = SOH_UNASSIGNED;

enum soh_format {
   SOH_FMT_TEXT,
   SOH_FMT_MSEED
} soh_fmt = SOH_FMT_TEXT;

struct si {
   char *key;
   enum soh_info val;
} soh_item [] = {
   { "T", SOH_TEMP},
   { "Z", SOH_MASS1_V},
   { "N", SOH_MASS2_V},
   { "E", SOH_MASS3_V},
   { "V", SOH_SUPPLY_V},
   { "P", SOH_POS}
};
#define N_SOHI (sizeof(soh_item)/sizeof(struct si))

struct sf {
   char *key;
   enum soh_format val;
} soh_fmts[] = {
   { "text", SOH_FMT_TEXT},
   { "mseed", SOH_FMT_MSEED}
};
#define N_SOHF (sizeof(soh_fmts)/sizeof(struct sf))

time_t lptm;

struct sstate {
   FILE *fd;
   char *chid;
   int blkno;
   char msg;
};

struct sstate strm[3] = {
   {NULL, "BHZ", 1, 1},
   {NULL, "BHN", 1, 1},
   {NULL, "BHE", 1, 1},
};

struct sstate sohd = {
   NULL, "SOH", 1, 1
};

struct sloc {
   int lat, lon, elev;  /* Degrees N & E, meters */
};

/* Blockette buffer for SOH output in MSEED data form */
uint64_t sohtim;
int sohblk = 0, sohdt = 60, sohcnt = 0;
unsigned char sohmsd[512];

void usage(){
   char *msg =
   " {-h | -v | -z <file> | -n <file> | -e <file> |\n"
   "        -soh <file> -item <itms> | -l [+|-] [jun|dec] <year>} ... <store>\n"
   " Options:\n"
   "   -h - usage (this text)\n"
   "   -v - verbose output (repeat for more verbosity)\n"
   "   -z <file> - Dump MSEED blockettes for Z component to named file\n"
   "   -n <file> - Dump MSEED blockettes for N component to named file\n"
   "   -e <file> - Dump MSEED blockettes for E component to named file\n"
   "   -S <name> - Explicitly set station name\n"
   "   -N <name> - Explicitly set network ID\n"
   "   -soh <file> - Dump SOH detail in named file\n"
   "   -sohdt <sec> - SOH sampling is every <sec> seconds (default 60)\n"
   "   -item {T|Z|N|E|V|P} - SOH item to dump.  Encoding:\n"
   "      T - temperature in logger (C)\n"
   "      V - power supply voltage (mV)\n"
   "      P - position (lat N, lon E, elev m) [text-only option]\n"
   "      Z, N, E - mass position (V)\n"
   "   -fmt {text|mseed} - SOH dump format; one is human-readable, the other\n"
   "      is a time series of MSEED data packets.\n"
   "   -l [+|-] [jun|dec] <year> - Describe leap second in store time\n"
   "      span.  Data in blockettes spanning the leap second will be flagged\n"
   "      appropriately in the Activity field of the blockette so that\n"
   "      time stamps may be reckoned correctly.  Sign of leap second, month\n"
   "      and year of application must be specified, e.g.\n"
   "         -l + jun 2012\n"
   "      describes the June 2012 leap second (positive).\n"
   "   <store> - store file to search.  This should be the first store file\n"
   "      in a group describing a store, and a name that includes the suffix\n"
   "      \"001.store\"  The rest of the store's file names are derived from\n"
   "      this.\n";
   fprintf(stderr, "Usage: %s%s", prog, msg);
   fflush(stderr);
}

void err(char *msg){
   fprintf(stderr, "%s: %s\n", prog, msg); fflush(stderr);
   exit(1);
}

void erroff(size_t off, char *msg){
   fprintf(stderr, "%s: at offset %zx, %s\n", prog, off, msg); fflush(stderr);
   exit(1);
}

void errcnt(int pos, char *msg){
   fprintf(stderr, "%s: at offset %x, %s\n", prog, pos, msg); fflush(stderr);
   exit(1);
}

int hw(unsigned char *p){
   return (p[0] << 8) | p[1];
}

int fw(unsigned char *p){
   return (p[0] << 24) | (p[1] << 16) | (p[2] <<  8) | p[3];
}

uint64_t dw(unsigned char *p){
#define gp(n)((uint64_t)p[n])
   return (gp(0)<< 56) | (gp(1)<< 48) | (gp(2)<< 40) | (gp(3)<< 32) 
        | (gp(4)<< 24) | (gp(5)<< 16) | (gp(6)<<  8) | gp(7);
}

void phw(unsigned char *p, int v){
   p[1] = v & 0xff; p[0] = (v >> 8) & 0xff;
}

void pfw(unsigned char *p, int v){
   p[3] = v         & 0xff; p[2] = (v >> 8)  & 0xff;
   p[1] = (v >> 16) & 0xff; p[0] = (v >> 24) & 0xff;
}

void bufsoh(
   char code[5], uint64_t ptim, struct sloc loc, int buflen, unsigned char buf[]
){
   size_t off = 0;
   struct timeval tv;
   struct tm *tm;
   enum {XX, LL=11, HW = 1, FW = 3, FL = 4} any = XX; /* Bkette 1000 codes */
   int ifw;
   short ihw;
   float ifl;

   /* Decode time */
   tv.tv_sec = ptim/1000000000l;
   tv.tv_usec = (ptim%1000000000l)/1000;
   tm = gmtime(&tv.tv_sec);

   /* Parse buffer to find interesting bit */
   while (off < buflen) {
      unsigned short siz = hw(buf+off) & 0x1fff, type = hw(buf+off+2);
      union { unsigned int fw; float fl; } u;
      switch (type) {
      case 0xa781:    /* Temperature, SOH voltages */
         if (soh_itm == SOH_TEMP) u.fw = fw(buf+off+9), any=FL;
         if (soh_itm == SOH_MASS1_V) u.fw = fw(buf+off+0x36), any=FL;
         if (soh_itm == SOH_MASS2_V) u.fw = fw(buf+off+0x3f), any=FL;
         if (soh_itm == SOH_MASS3_V) u.fw = fw(buf+off+0x48), any=FL;
	 if (any==FL) ifl = u.fl;
	 break;
      case 0xab81:    /* Environmental */
         if (soh_itm == SOH_SUPPLY_V) ihw = hw(buf+off+0x15), any=HW;
	 break;
      }
      off += siz;
   }
   if (any == XX && soh_itm == SOH_POS) any = LL;
   if (any != XX){
      short itmsiz;
      int dtnow;
      double dtms;
      switch (soh_fmt){
      case SOH_FMT_TEXT:
	 fprintf(sohd.fd, "%04d/%02d/%02d %02d:%02d:%02d.%03d ",
	    1900+tm->tm_year, 1+tm->tm_mon, tm->tm_mday,
	    tm->tm_hour, tm->tm_min, tm->tm_sec, tv.tv_usec/1000);
	 switch (any) {
	 case HW:
	    fprintf(sohd.fd, "%d\n", ihw);
	    break;
	 case FW:
	    fprintf(sohd.fd, "%d\n", ifw);
	    break;
	 case FL:
	    fprintf(sohd.fd, "%f\n", ifl);
	    break;
	 case LL:
	    fprintf(sohd.fd, "%f %f %d\n",
	       1e-6*(float)loc.lat, 1e-6*(float)loc.lon, loc.elev);
	    break;
	 default:
	    fprintf(sohd.fd, "(unknown datatype)\n");
	 }
	 break;
      case SOH_FMT_MSEED:
         itmsiz = (any == HW) ? 2 : 4;
	 dtms = (ptim - sohtim)/1000000;
	 dtnow = 1e-3*dtms;
         if (sohcnt > 1) {
	    /* SOH sample rate is usually long, from 5 s to 3600 s.
	       If this is exceeded by 2.5 s, then declare a time discontinuity
               and dump the data accumulated so far.
	    */
	    int writ = 0;
	    float chk = fabs(sohdt-1e-3*((ptim - sohtim)/1000000));
	    if (dtnow>0 && abs(sohdt-dtnow) >= sohdt/6) {
	       if (verb) printf("SOH gap at "
	             "%04d/%02d/%02d %02d:%02d:%02d.%03d, %.4f s\n",
		     1900+tm->tm_year, 1+tm->tm_mon, tm->tm_mday,
		     tm->tm_hour, tm->tm_min, tm->tm_sec, tv.tv_usec/1000,
                     chk);
	    }
	    /* Check if time discontinuity, dump blockette if so */
	    if (chk > sohdt/6 /* && sohcnt>20 */) writ = 1;
	    if (sohcnt*itmsiz >= sizeof(sohmsd)-64) writ = 1;
	    if (writ) {
	       phw(sohmsd+30, sohcnt); phw(sohmsd+32, -sohdt); /* count, SRF */
	       writ = fwrite(sohmsd, sizeof(sohmsd), 1, sohd.fd);
	       if (writ < 1)
	          errcnt(sohblk, "Error writing SOH output file");
	       sohcnt = 0;
	    }
	 }
         if (sohcnt == 0) {
	    /* Start of new buffer.  Build up MSEED header and type 1000
	       blockette */
	    int i;
	    sohblk += 1;
	    snprintf((char*)sohmsd, 7, "%06d", sohblk);     /* Block # 0-5 */
	    sohmsd[6] = 'D'; sohmsd[7] = ' ';        /* D flag  6-7   */
            for(i=0;i<5;i++)                         /* Station code 8-12 */
               sohmsd[8+i] = (snam[0] == ' ' ? code[i] : snam[i]);
	    sohmsd[13] = ' '; sohmsd[14] = ' ';      /* Loc ID 13-14 */
	    sohmsd[15] = 'L';                        /* Channel ID 15-17 */
	    if (soh_itm == SOH_TEMP){
	       sohmsd[16] = 'K'; sohmsd[17] = 'L';   /* Temp in logger */
	    } else {
	       sohmsd[16] = 'E'; sohmsd[17] = soh_itm;/* Voltage, in hole */
	    }
	    sohmsd[18] = snet[0]; sohmsd[19] = snet[1]; /* Network code 18-19 */
	    phw(sohmsd+20, 1900+tm->tm_year);        /* BTIME year 20-21 */
	    phw(sohmsd+22, 1+tm->tm_yday);           /* BTIME jday 22-23 */
	    sohmsd[24] = tm->tm_hour;                /* BTIME hour 24 */
	    sohmsd[25] = tm->tm_min;                 /* BTIME min 25 */
	    sohmsd[26] = tm->tm_sec;                 /* BTIME sec 26 */
	    sohmsd[27] = 0;                          /* BTIME align 27 */
	    phw(sohmsd+28, tv.tv_usec/100);          /* BTIME cus 28-29 */
	                                             /* (samples) 30-31 */
	    phw(sohmsd+32, 0); phw(sohmsd+34,  1);   /* SRF, SRM 32-35 */
	    sohmsd[36] = 0;                          /* Activity flag 36 */
	    sohmsd[37] = 0;                          /* I/O+clock flag 37 */
	    sohmsd[38] = 0;                          /* Quality flag 38 */
	    sohmsd[39] = 1;                          /* # blockettes 39 */
	    pfw(sohmsd+40,  0);                      /* Timing corr. 40-43 */
	    phw(sohmsd+44, 64);                      /* Start of data */
	    phw(sohmsd+46, 48);                      /* Start of blockettes */

	    /* Build blockette 1000 */
	    phw(sohmsd+48, 1000); phw(sohmsd+50,    0);
	    sohmsd[52] = any; sohmsd[53] = 1; sohmsd[54] = 9; sohmsd[55] = 0;

	    /* Clear data portion */
	    for (i=56;i<sizeof(sohmsd); i++) sohmsd[i] = 0;
	 }
	 if (itmsiz == 2)
	    phw(sohmsd+64+sohcnt*2, ihw);
	 else {
	    union { unsigned int fw; float fl;} u;
	    if (any == FL) {u.fl = ifl; ifw = u.fw;}
	    pfw(sohmsd+64+sohcnt*4, ifw);
	 }
	 /* Save for time continuity check */
	 sohtim = ptim;
	 sohcnt += 1;
      }
   }
}

void bufdat(
   int ix, char code[5], uint64_t ptim,
   int buflen, unsigned char buf[]
){
   int ndat = hw(buf+8), sps = hw(buf+12);
   int i, j, lim;
   unsigned char bkhdr[64], data[512];
   struct sstate *state = strm+ix;
   struct timeval tv;
   struct tm *tm;

   /* Decode time */
   tv.tv_sec = ptim/1000000000l;
   tv.tv_usec = (ptim%1000000000l)/1000;
   tm = gmtime(&tv.tv_sec);

   /* Build blockette header */
   snprintf((char*)bkhdr+0, 7, "%06d", state->blkno%1000000);
   bkhdr[6] = 'D'; bkhdr[7] = ' ';
   for(i=0;i<5;i++) bkhdr[8+i] = (snam[0] == ' ' ? code[i] : snam[i]);
   bkhdr[13] = ' '; bkhdr[14] = ' ';
   for(i=0;i<3;i++) bkhdr[15+i] = state->chid[i];
   bkhdr[18] = snet[0]; bkhdr[19] = snet[1];
   phw(bkhdr+20, tm->tm_year+1900);
   phw(bkhdr+22, tm->tm_yday+1);
   bkhdr[24] = tm->tm_hour;
   bkhdr[25] = tm->tm_min;
   bkhdr[26] = tm->tm_sec;
   bkhdr[27] = 0;
   phw(bkhdr+28,   tv.tv_usec/100);
   phw(bkhdr+30,   ndat);
   phw(bkhdr+32,   sps);
   phw(bkhdr+34,   1);
   bkhdr[36] = 0;   /* Activity flags: 0 */
   bkhdr[37] = 0;   /* I/O & Clock quality: 0 */
   bkhdr[38] = 0;   /* Data quality: 0 */
   bkhdr[39] = 1;   /* Number of data blockettes following */
   pfw(bkhdr+40,      0);   /* Time correction */
   phw(bkhdr+44,     64);   /* Data offset */
   phw(bkhdr+46,     48);   /* Data blockette offset */
   for(i=48;i<sizeof(bkhdr);i++) bkhdr[i] = 0;
   if (lpsc) {
      /* Check if leap second in this blockette and flag if so */
      double dt = difftime(lptm, tv.tv_sec) - 1e-6*tv.tv_usec;
      double sr = sps;
      if (dt > 0 && dt <= ndat/sr) {
         bkhdr[36] |= lpsc;
	 if (verb) printf("%s: leap second straddle %s block %d\n",
	    prog, state->chid, state->blkno);
      }
   }

   phw(bkhdr+48+0, 1000);   /* Type 1000 data blockette */
   phw(bkhdr+48+2,    0);   /* Next 0 */
   bkhdr[48+4] = 10;/* Encoding format: Steim I */
   bkhdr[48+5] = 1; /* Word order: big-endian */
   bkhdr[48+6] = 9; /* Record length: 2**9 (512) */
   bkhdr[48+7] = 0; /* Reserved byte zeroed */

   /* Write header */
   i = fwrite(bkhdr, sizeof(bkhdr), 1, state->fd);
   if (i != 1) errcnt(state->blkno, "Error writing blockette (hdr)");

   j = buflen-14; lim = sizeof(data)-sizeof(bkhdr);
   if (j > lim) {
      fprintf(stderr, "%s: %s data block %d > 512 (len is %d); truncated\n",
         prog, state->chid, state->blkno, j);
      j = lim;
   }
   for(i=0; i<j; i++) data[i] = buf[14+i]; for(;i<lim; i++) data[i] = 0;
   i = fwrite(data, lim, 1, state->fd);
   if (i != 1) errcnt(state->blkno, "Error writing blockette (data)");

   state->blkno += 1;
}

/* Process packet */

void dhdr(off_t off, size_t siz, unsigned char buf[]){
   /* Payload types: (v2)
      c3 - alert information
      c0 - configuration information (zipped data? contains "PK" and "zip")
      a5 - log data, trigger info ?
      a3 - telemetry log data ?
      a1 - ARM log data ?
      9f - Java log data, extension 00; size is length of text?;
           9 bytes of control info, then text.
      9b - ? something with its own internal sequence number
      99 - ? something with a lat and lon attached; temperature/mass pos?
           time sequence is about every 10 minutes; payload length is 58,
	   59 or 60.  name is always 0xab, addition is always 00.
      89 - 1000 1001 stream 1
      8b - 1000 1011 stream 2
      8d - 1000 1101 stream 3
   */
   struct sloc loc;
   uint64_t pkttim;
   int datlen, datix, datoff, nsamp, rval, rmul, band, extoff, iid;
   char id[6];
   if (buf[0] != 'N' || buf[1] != 'P') erroff(off, "bad packet header");
   band = buf[34];
   switch (band) {
   case 0x89: case 0x8b: case 0x8d:
      extoff = hw(buf+35) & 0xffff;
      if (extoff)
         fprintf(stderr, "%s: At %zx data packet ext is %04x not zero\n",
	    prog, (size_t)off, extoff);
      if (buf[39])
         fprintf(stderr, "%s: At %zx data packet name is %02x not zero\n",
	    prog, (size_t)off, extoff);
      if (buf[40] != 0x83)
         fprintf(stderr,
	    "%s: At %zx data packet type is %02x not 0x83 (Steim1)\n",
	    prog, (size_t)off, buf[40]);
      extoff = hw(buf+41);
      if (extoff != 8)
         fprintf(stderr,
	    "%s: At %zx data packet has extension %04x not 8\n",
	    prog, (size_t)off, extoff);
      break;
   case 0x99:
      extoff = hw(buf+41) & 0xffff;
      if (extoff) {
         fprintf(stderr, "%s: At %zx SOH packet ext is %04x not zero\n",
	    prog, (size_t)off, extoff);
      }
      break;
   default:
      return;
   }
   datoff = 37;
   datlen = siz-datoff;             /* Length of data in packet */
   pkttim = dw(buf+12);
   iid = hw(buf+32) & 0xffff;       /* Turn s/n into station name */
   snprintf(id, 6, "%05d", iid%10000); id[0] = "0123456789ABCDEF"[iid/10000];
   switch (band) {
   case 0x89: case 0x8b: case 0x8d:
      datix = (band-0x89)>>1;       /* Turn into index 0 = Z, 1 = N, 2 = E */
      if (NULL == strm[datix].fd) {
         if (strm[datix].msg) {
            fprintf(stderr, "%s: %s data skipped (output file not assigned)\n",
               prog, strm[datix].chid);
	    strm[datix].msg = 0;
	 }
      } else
	 bufdat(datix, id, pkttim, datlen, buf+datoff); /* Process buffer */
      break;
   case 0x99:
      loc.lat = fw(buf+20); loc.lon = fw(buf+24); loc.elev = hw(buf+28);
      if (sohd.fd)
         bufsoh(id, pkttim, loc, datlen, buf+datoff);  /* Process buffer */
      break;
   }
}

/* Check if end of data in buffer */

int ckend(char buf[]){
   if (buf[0] != 'E') return 0;
   if (buf[1] != 'N') return 0;
   if (buf[2] != 'D') return 0;
   if (buf[3] != 'O') return 0;
   if (buf[4] != 'D') return 0;
   if (buf[5] != 'A') return 0;
   if (buf[6] != 'T') return 0;
   if (buf[7] != 'A') return 0;
   return 1;
}

/* Check type of packet in buffer */

int cktype(char buf[]){
   /* Version 3 ID = 'np'; version 2 ID = 'NP' */
   if (buf[0] != 'N') return 0;
   if (buf[1] != 'P') return 0;
   return 1;
}

/* Return size of file minus size of volume header */

size_t fsize(FILE *fd){
   off_t off = ftello(fd);
   off_t siz;
   (void)fseeko(fd, 0, SEEK_END);
   siz = ftello(fd);
   (void)fseeko(fd, off, SEEK_SET);
   return (size_t) siz - HDRSIZ;
}

struct aloc_t {
   off_t off;
   size_t siz;
   int fnum;
} *aloc;

int main(int argc, char *argv[]){
   FILE *fd;
   off_t off;
   size_t siz, tmp, atsiz, fsiz, scum;
   char ok = 1;
   char *cbuf, *store = NULL;
   int i, six, fno, store_size;
   char buf[0x100000];

   prog = argv[0];

   for(i=0;i<sizeof(snam);i++) snam[i] = ' ';
   for(i=0;i<sizeof(snet);i++) snet[i] = 'Y';

   for(i=1; i<argc; i++) {
      if (argv[i][0] == '-') { /* Check for option */
         if (0 == strcmp(argv[i], "-z")) {
	    i += 1;
	    strm[0].fd = fopen(argv[i], "w");
	    if (strm[0].fd == NULL) err("bad -z file name");
         } else if (0 == strcmp(argv[i], "-e")) {
	    i += 1;
	    strm[2].fd = fopen(argv[i], "w");
	    if (strm[2].fd == NULL) err("bad -e file name");
         } else if (0 == strcmp(argv[i], "-n")) {
	    i += 1;
	    strm[1].fd = fopen(argv[i], "w");
	    if (strm[1].fd == NULL) err("bad -n file name");
         } else if (0 == strcmp(argv[i], "-soh")) {
	    i += 1;
	    sohd.fd = fopen(argv[i], "w");
	    if (sohd.fd == NULL) err("bad -soh file name");
         } else if (0 == strcmp(argv[i], "-S")) {
	    i += 1; six = strlen(argv[i]);
	    memcpy(snam,argv[i],six>sizeof(snam)?sizeof(snam):six);
         } else if (0 == strcmp(argv[i], "-N")) {
	    i += 1; six = strlen(argv[i]);
	    memcpy(snet,argv[i],six>sizeof(snet)?sizeof(snet):six);
         } else if (0 == strcmp(argv[i], "-sohdt")) {
            char *p;
	    i += 1; six = strlen(argv[i]);
            sohdt = strtol(argv[i],&p,10);
            if (p-argv[i] != six) err("bad -sohdt value");
         } else if (0 == strcmp(argv[i], "-item")) {
	    int j;
	    for (j=0;j<N_SOHI;j++){
	       if (0 == strcmp(argv[i+1], soh_item[j].key)) {
	          soh_itm = soh_item[j].val;
		  break;
	       }
	    }
	    if (j>=N_SOHI) err("bad SOH -item name");
	    i += 1;
         } else if (0 == strcmp(argv[i], "-fmt")) {
	    int j;
	    for (j=0;j<N_SOHF;j++){
	       if (0 == strcmp(argv[i+1], soh_fmts[j].key)) {
	          soh_fmt = soh_fmts[j].val;
		  break;
	       }
	    }
	    if (j>=N_SOHF) err("bad SOH -fmt name");
	    i += 1;
	 } else if (0 == strcmp(argv[i], "-l")) {
	    /* Parse leap second syntax: -l {+/-} {jun|dec} <year> */
	    int dir;
	    struct tm tm;
	    if (argc < i+3) {
	       fprintf(stderr, "missing -l args\n"); continue;
	    }
	    if (0 == strcmp(argv[i+1], "-")) 
	       tm.tm_sec = 59, dir = 0x10;
	    else if (0 == strcmp(argv[i+1], "+")) 
	       tm.tm_sec = 60, dir = 0x20;
	    else {
	       i += 1;
	       fprintf(stderr, "bad -l arg: + or -\n"); continue;
	    }
	    if (0 == strcmp(argv[i+2], "jun")) {
	       tm.tm_mon = 6-1;
	       tm.tm_mday = 30-1;
	    } else if (0 == strcmp(argv[i+2], "dec")) {
	       tm.tm_mon = 12-1;
	       tm.tm_mday = 31-1;
	    } else {
	       i += 2;
	       fprintf(stderr, "bad -l arg: jun or dec\n"); continue;
	    }
	    tm.tm_year = strtol(argv[i+3], NULL, 10) - 1900;
	    if (tm.tm_year<=0) {
	       i += 3;
	       fprintf(stderr, "bad -l year\n"); continue;
	    }
	    tm.tm_hour = 23;
	    tm.tm_min = 59;
	    lptm = mktime(&tm);
	    lpsc = dir;
	    i += 3;
         } else if (0 == strcmp(argv[i], "-v")) {
	    verb += 1;
         } else if (0 == strcmp(argv[i], "-h")) {
	    usage();
	 } else {
	    fprintf(stderr, "bad arg (ignored): %s\n", argv[i]);
	 }
      } else {
         store = argv[i];
      }
   }

   if (soh_itm == SOH_POS
    && soh_fmt != SOH_FMT_TEXT) err("SOH P item only -fmt text, sorry");

   /* Open store file */

   if (store == NULL) err("no store file given");
   fd = fopen(store, "r");
   if (fd == NULL) err("bad store file name");

   /* Verify NMX volume, read allocation table */

   siz = fread(buf, 48, 1, fd);

   if(strncmp(buf, "NMXV", 4) != 0) err("not a NMX store");

   if(strncmp(buf+32, "VOLFALOC", 8) != 0) err("missing allocation table");

   /* Find store file number position */
   cbuf = strstr(store, "001.store");
   if(cbuf == NULL)
      err("unusual store name (looking for 001.store suffix) -- correct?");
   six = cbuf-store;

   fsiz = fsize(fd);
   scum = 0, fno = 1;
   if (verb) printf("store file %s size %zx\n", store, fsiz);

   /* Decode table */
   siz = fw((unsigned char*)buf+32+8); tmp = fw((unsigned char*)buf+32+12);
   store_size = (int)siz;
   aloc = calloc(siz, sizeof(struct aloc_t));
   if (aloc == NULL) err("allocation table error");
   cbuf = malloc(tmp);
   if (cbuf == NULL) err("table buffer error");
   tmp = fread(cbuf, tmp-48, 1, fd);
   for(i=0;i<siz;i++){
      int j = i*16;
      aloc[i].off = (off_t)dw((unsigned char*)cbuf+j+ 4) - scum;
      aloc[i].siz = fw((unsigned char*)cbuf+j+12);
//    printf("%d off %zx\n",i, (size_t)aloc[i].off);
      if (aloc[i].off >= fsiz) {
         char *tmp = strdup(store);
         fno += 1; scum += fsiz;
         aloc[i].off = (off_t)dw((unsigned char*)cbuf+j+ 4) - scum;
	 sprintf(tmp+six, "%03d.store", fno);
	 fclose(fd);
	 fd = fopen(tmp, "r");
         if (fd == NULL) err("bad store file name");
         fsiz = fsize(fd);
	 if (verb) printf("store file %s size %zx\n", tmp, fsiz);
	 free(tmp);
	 if (fsiz <= 0) break;
      }
      aloc[i].fnum = fno;
   }
   free(cbuf);
   if (verb) printf("store size %d (%x)\n", store_size, store_size);

   /* Process each part of allocation table */

   atsiz = siz; fno = 1; fclose(fd); fd = fopen(store, "r");
   for(i=0; i<atsiz; i++){
      if (verb>1) printf("alloc tbl walk: %d fno %d off %zx: ",
         i, aloc[i].fnum, (size_t)aloc[i].off);
      if (fno != aloc[i].fnum) {
         char *tmp = strdup(store);
         fno = aloc[i].fnum;
	 sprintf(tmp+six, "%03d.store", fno);
	 fclose(fd);
	 fd = fopen(tmp, "r");
         if (fd == NULL) err("bad store file name");
	 free(tmp);
      }
      off = fseeko(fd, aloc[i].off, SEEK_SET);

      siz = fread(buf, 68, 1, fd);

      if (strncmp(buf+36, "CHTB", 4) == 0) {
	 if (verb>1) printf("CHTB: %zx, %zx\n", (size_t)off, aloc[i].siz);
      } else if (strncmp(buf+36, "CSTB", 4) == 0) {
	 if (verb>1) printf("CSTB: %zx, %zx\n", (size_t)off, aloc[i].siz);
      } else if (strncmp(buf+36, "CLUS", 4) == 0) {
	 if (verb>1) printf("CLUS: %zx, %zx\n", (size_t)off, aloc[i].siz);
         off = aloc[i].off+68;
	 do {
	    int writ = fread(buf, 40, 1, fd);
	    if (writ <= 0)
	       erroff(off, "Zero read from store file");
	    if (ckend(buf)) break;
	    if (!cktype(buf)) erroff(off,"packets not from V2 store");
	    siz = hw((unsigned char*)buf+2) & 0xffff;
	    if (siz > 40)
	       writ = fread(buf+40, siz-40, 1, fd);
	    if (writ <= 0)
	       erroff(off, "Incomplete data read from store file");
	    dhdr(off, siz, (unsigned char*)buf);
	    off += siz + /* Seems to be necessary to round to word boundary */
	           ((0x03 & siz)?4-(0x03&siz):0);
	    writ = fseeko(fd, off, SEEK_SET);
	    if (writ) erroff(off,"bad seek in cluster");
	 } while(ok);
      } else {
        fprintf(stderr,"%-4.4s -- unrecognized\n", buf+36);
	erroff(aloc[i].off,"unrecognized table section");
      }
   }

   if (sohd.fd && soh_fmt == SOH_FMT_MSEED && sohcnt) {
      phw(sohmsd+30, sohcnt); phw(sohmsd+32, -sohdt); /* count, SRF */
      i = fwrite(sohmsd, sizeof(sohmsd), 1, sohd.fd);
      if (i<=0)
         errcnt(sohblk, "error flushing SOH MSEED data");
   }

   return 0;
}
