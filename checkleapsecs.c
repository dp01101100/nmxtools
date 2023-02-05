/* Program to check whether system time arithmetic accounts for leap seconds
   in its time base.

   G. Helffrich/U. Bristol
      26 Aug. 2012
*/

#include <unistd.h>
#include <stdlib.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <math.h>
#include <time.h>


struct lpsec {
   int year;
   char injun, indec;
};

struct lpsec sched[] = {
    {1972, +1, +1},
    {1973,  0, +1},
    {1974,  0, +1},
    {1975,  0, +1},
    {1976,  0, +1},
    {1977,  0, +1},
    {1978,  0, +1},
    {1979,  0, +1},
    {1981, +1,  0},
    {1982, +1,  0},
    {1983, +1,  0},
    {1985, +1,  0},
    {1987,  0, +1},
    {1989,  0, +1},
    {1990,  0, +1},
    {1992, +1,  0},
    {1993, +1,  0},
    {1994, +1,  0},
    {1995,  0, +1},
    {1997, +1,  0},
    {1998,  0, +1},
    {2005,  0, +1},
    {2008,  0, +1},
    {2012, +1,  0},
};
#define N_leap (sizeof(sched)/sizeof(struct lpsec))

char *prog;
unsigned char odeb = 0;

int main(int argc, char *argv[]) {
   struct tm tm = {.tm_isdst = 0};
   time_t bls, als;
   int i, cumoff = 0, cumgps = 0;
   double dt;
   
   prog = argv[0];

   for(i=1;i<argc;i++){
      if (0 == strcmp(argv[i],"-d"))
         odeb = 1;
      else {
         fprintf(stderr, "%s: Invalid option: %s (ignored).\n",
	    prog, argv[i]);
      }
   }

   /* Loop over leap seconds */
   for(i=0;i<N_leap;i++){
      if (sched[i].injun) {
         tm.tm_sec = 59;
         tm.tm_min = 59;
         tm.tm_hour = 23;
         tm.tm_mon = 6-1;
         tm.tm_mday = 30-1;
         tm.tm_year = sched[i].year;
	 bls = timegm(&tm);
         tm.tm_sec = 00;
         tm.tm_min = 00;
         tm.tm_hour = 00;
         tm.tm_mon = 7-1;
         tm.tm_mday = 1-1;
	 als = timegm(&tm);
	 dt = difftime(als, bls);
	 if (fabs(dt-2) > 1e-5) {
	    if (sched[i].year >= 1980) cumgps += 1;
	    cumoff += 1;
	    printf("Leap second %d (June) not accounted for (dt %f).\n",
	       sched[i].year, dt);
	    if(odeb)printf("%lx - %lx = %f\n", als, bls, dt);
	 }
      }
      if (sched[i].indec) {
         tm.tm_sec = 59;
         tm.tm_min = 59;
         tm.tm_hour = 23;
         tm.tm_mon = 12-1;
         tm.tm_mday = 31-1;
         tm.tm_year = sched[i].year;
	 bls = timegm(&tm);
         tm.tm_sec = 00;
         tm.tm_min = 00;
         tm.tm_hour = 00;
         tm.tm_mon = 1-1;
         tm.tm_mday = 1-1;
         tm.tm_year = sched[i].year+1;
	 als = timegm(&tm);
	 dt = difftime(als, bls);
	 if (fabs(dt-2) > 1e-5) {
	    if (sched[i].year >= 1980) cumgps += 1;
	    cumoff += 1;
	    printf("Leap second %d (Dec.) not accounted for (dt %f).\n",
	       sched[i].year, dt);
	    if(odeb)printf("%lx - %lx = %f\n", als, bls, dt);
	 }
      }
   }

   printf("Cumulative computer clock offset to end %d is %d seconds.\n",
      sched[N_leap-1].year, cumoff);
   printf("Cumulative GPS clock offset to end %d is %d seconds.\n",
      sched[N_leap-1].year, cumgps);
   return 0;
}
