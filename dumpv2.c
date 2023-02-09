/* Dump Taurus v2 packets to figure out store format

   G. Helffrich/ELSI/Tokyo Tech.
   8 Feb. 2023

*/

#include <unistd.h>
#include <stdlib.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <time.h>

char *prog, cmap[256];

short wo;                          /* word order: 0 - le, 1 - be */

int odmp;

void err(char *msg){
   fprintf(stderr, "%s: %s\n", prog, msg); fflush(stderr);
   exit(1);
}

void erroff(size_t off, char *msg){
   fprintf(stderr, "%s: at offset 0x%zx, %s\n", prog, off, msg); fflush(stderr);
   exit(1);
}

int hw(unsigned char *p){
   return (p[0] << 8) | p[1];
}

int fw(unsigned char *p){
   return (p[0] << 24) | (p[1] << 16) | (p[2] <<  8) | p[3];
}

/* Check if end of data in buffer */

int ckend(unsigned char buf[]){
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

/* Check for store header */

int dfhd(off_t off, unsigned char buf[]){

   off_t siz;

   if (
      (buf[0] != 'N') ||
      (buf[1] != 'M') ||
      (buf[2] != 'X') ||
      (buf[3] != 'V') ||

      (buf[32] != 'V') ||
      (buf[33] != 'O') ||
      (buf[34] != 'L') ||
      (buf[35] != 'F')
   ) return 0;

   siz = fw(buf+16);
   printf("NMX store header at %llx, size (hex) %llx\n", off, siz);
   return 1;
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
   int seq = fw(buf+4);
   int siz = hw(buf+2);
   int i, eop, next;

   printf("%zx %02d %04d ", (size_t)off, buf[31], hw(buf+32));
   u.w[1-wo] = fw(buf+12); u.w[wo] = fw(buf+16);
   tv.tv_sec = u.nsec/1000000000l;
   tv.tv_usec = (u.nsec%1000000000l)/1000;
   tm = gmtime(&tv.tv_sec);
   printf("%4d/%02d/%02d %02d:%02d:%02d.%03d ",
      tm->tm_year+1900, tm->tm_mon+1, tm->tm_mday,
      tm->tm_hour, tm->tm_min, tm->tm_sec, tv.tv_usec/1000);
      for(i=0; i<8; i++) printf("%02x",buf[8+i]);         /* Time in hex */
   printf(" %04d %04d\n", seq, siz);
   printf(" %8.3f %9.3f %4dm ",
      ((float)(fw(buf+20)))*1e-6,
      ((float)(fw(buf+24)))*1e-6,
      hw(buf+28));
   i = hw(buf+30) & 0x0f;
   printf("%s %04d ",
      (i == 11) ? "Taurus" : ((i == 13) ? "Trident" : "(unknown)"),
      hw(buf+32));
   printf("band %02x seq %d\n", buf[34], fw(buf+8));
   eop = 37;
   next = hw(buf+35);
   if (next && odmp) {
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
   }
   eop += next;
   if (!odmp) return siz;

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
   off_t off = 0;
   size_t siz;
   char ok = 1;
   char *cbuf, *store = NULL, *ptr;
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
         switch (argv[i][1]) {
         case 'd':             /* -d */
            odmp = 1;
            break;
         case 'o':             /* -o <offset> */
            i += 1; off = strtoull(argv[i], &ptr, 16);
            if ((ptr-argv[i] < strlen(argv[i])) || off == 0) goto bad;
            break;
         default:
            goto bad;
         }
         continue;
bad:
	 fprintf(stderr, "%s: **Bad arg (ignored): %s\n", prog, argv[i]);
      } else {
         store = argv[i];
      }
   }

   /* Open file */

   if (store == NULL) err("no packet file given");
   fd = fopen(store, "r");
   if (fd == NULL) err("bad packet file name");
   if (off == 0) {
      siz = fread(buf, sizeof(char), 68, fd);
      if (68 != siz || !dfhd(off, buf)) err("not a store file");
      off += 68;
   } else 
      if (0 != fseeko(fd, off, SEEK_SET)) erroff(off, "bad initial offset");

   do {
      int psiz;

      siz = fread(buf, sizeof(char), 37, fd);
      if (siz <= 0) break;
      if (ckend(buf)) {
         off += 0x100000; off &= ~0xfffff; /* Keep going until EOF */
         off += 0x44;
      } else {
         if (buf[0] != 'N' || buf[1] != 'P') erroff(off, "bad packet header");
         psiz = hw(buf+2);
         if (psiz-37 != fread(buf+37, sizeof(char), psiz-37, fd))
            erroff(off, "end of file");
         siz = dhdr(off, buf);
         off += (siz+3) & ~0x03;        /* Round to word multiple */
      }
      if (0 != fseeko(fd, off, SEEK_SET)) erroff(off, "bad offset");
   } while(ok);

   fclose(fd);
   return 0;
}
