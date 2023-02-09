/* Dump Taurus v3 packets to figure out store format

   G. Helffrich/U. Bristol
   23 Aug. 2012, last update
      9 Feb. 2023

*/

#include <unistd.h>
#include <stdlib.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <time.h>

char *prog, cmap[256];

short wo;                          /* word order: 0 - le, 1 - be */

void err(char *msg){
   fprintf(stderr, "%s: %s\n", prog, msg); fflush(stderr);
   exit(1);
}

void erroff(size_t off, char *msg){
   fprintf(stderr, "%s: at offset %zx, %s\n", prog, off, msg); fflush(stderr);
   exit(1);
}

int hw(unsigned char *p){
   return (p[0] << 8) | p[1];
}

int fw(unsigned char *p){
   return (p[0] << 24) | (p[1] << 16) | (p[2] <<  8) | p[3];
}

/* Dump packet header and text */

int dhdr(off_t off, unsigned char buf[]){
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

   struct timeval tv;
   struct tm *tm;
   union {
      uint64_t nsec;
      uint32_t w[2];
   } u;
   int seq = fw(buf+4) >> 8;
   int siz = hw(buf+2) & 0x1fff;
   int flg = buf[2] >> 5;
   int i, eop, next;

   if (flg & 0x01) eop = 37; else eop = 30;
   if (flg & 0x02) siz += hw(buf+eop) << 13, eop += 2;
   printf("%zx %02d %04d ", (size_t)off, buf[24], hw(buf+25));
   u.w[1-wo] = fw(buf+8); u.w[wo] = fw(buf+12);
   tv.tv_sec = u.nsec/1000000000l;
   tv.tv_usec = (u.nsec%1000000000l)/1000;
   tm = gmtime(&tv.tv_sec);
   printf("%4d/%02d/%02d %02d:%02d:%02d.%03d ",
      tm->tm_year+1900, tm->tm_mon+1, tm->tm_mday,
      tm->tm_hour, tm->tm_min, tm->tm_sec, tv.tv_usec/1000);
      for(i=0; i<8; i++) printf("%02x",buf[8+i]);         /* Time in hex */
   printf(" %04d %04d\n", seq, siz);
   /* Decode flags */
   printf(" (");
      if (flg & 0x04) printf("ext. blk.,");
      if (flg & 0x02) printf("long size,");
      if (flg & 0x01) printf("full band name,");
   printf(") ");
   printf(" Clock ");
      flg = buf[7];
      if ((flg & 0x0c) == 0) printf("(no status)");
      if ((flg & 0x0c) == 4) printf("incorrect");
      if (flg & 0x08) {
         if (flg & 0x08) printf("correct,");
         if (~flg & 0x04) printf("not "); printf("locked,");
      }
      if (flg & 0x02) printf("calibrating,");
      if (flg & 0x01) printf("ReTx,");
   printf(" %8.3f %9.3f ",
      ((float)(fw(buf+16)))*1e-6,
      ((float)(fw(buf+20)))*1e-6);
   printf("band %d seq %d named ", buf[27], buf[28]);
      if (buf[2]>>5 & 0x01)
         printf("%08x%08x", fw(buf+29), fw(buf+33));
      else
         printf("%3d",buf[29]);
      printf("\n");
   next = buf[eop];
   if (next) {
      char str[16];
      printf("Extension (%d bytes):", next);
      for(i=0;i<next;i++) {
         if (i%16 == 0) {
	    if (i) printf("     *%16.16s*",str);
	    printf("\n ");
	 }
         printf(" %02x", buf[eop+1+i]); str[i%16] = cmap[buf[eop+1+i]];
      }
      if (i%16) {
         int j, k=i%16, l=16-k;
         for(j=1; j<=l; j++) printf("   "); printf("     *%*.*s*", k, k, str);
      }
      eop += next;
   }
   printf("\nContent (%d bytes):", siz-eop);
   {  char str[16];
      for (i=0; i<siz-eop && i<64; i++) {
         if (i%16 == 0) {
	    if (i) printf("     *%16.16s*",str);
	    printf("\n ");
	 }
         printf(" %02x", buf[eop+1+i]); str[i%16] = cmap[buf[eop+1+i]];
      }
      if (i != siz-eop) printf(" ... "); else printf("     ");
      if (i%16 || i==64) {
         int j, k=i%16, l=16-k;
         if (i!=64) for(j=1; j<=l; j++) printf("   "); else k=16;
	    printf("*%*.*s*", k, k, str);
      }
   }
   printf("\n");

   return siz;
}

int main(int argc, char *argv[]){
   FILE *fd;
   off_t off;
   size_t siz;
   char ok = 1;
   char *cbuf, *store = NULL;
   int i;
   unsigned char buf[0x100000];

   prog = argv[0];
   i = 1; wo = ((char *)&i) == 0;

   /* Set up character map */
   for(i=0;i<256;i++) cmap[i] = '.';
   cbuf = "0123456789"
      "abcdefghijklmnopqrstuvwxyz"
      "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
      "!@#$%^&*()_+-={}[]:|;'\\\"~`<>?,./ ";
/*    "§±!@#$%^&*()_+-={}[]:|;'\\\"~`<>?,./ "; */
   for(i=0; i<strlen(cbuf); i++) cmap[(unsigned char)(cbuf[i])] = cbuf[i];

   for(i=1; i<argc; i++) {
      if (argv[i][0] == '-') { /* Check for option */
	 fprintf(stderr, "bad arg (ignored): %s\n", argv[i]);
      } else {
         store = argv[i];
      }
   }

   /* Open file */

   if (store == NULL) err("no packet file given");
   fd = fopen(store, "r");
   if (fd == NULL) err("bad packet file name");
   off = 0;

   do {
      int flg, psiz, pesiz;

      siz = fread(buf, 29, 1, fd);
      if (siz <= 0) break;
      psiz = hw(buf+2) & 0x1fff;           /* Mask flags in high bits */
      if (buf[0] != 'n' || buf[1] != 'p') erroff(off, "bad packet header");
      flg = hw(buf+2) >> 13;
      if (flg & 0x01) pesiz = 8; else pesiz = 1;
      if (flg & 0x02) pesiz += 2;
      siz = fread(buf+29, pesiz, 1, fd);
      if (flg & 0x02) psiz |= hw(buf+29+pesiz-2) << 13;
      siz = fread(buf+29+pesiz, psiz-(29+pesiz), 1, fd);
      siz = dhdr(off, buf);
      off += siz;
   } while(ok);

   fclose(fd);
   return 0;
}
