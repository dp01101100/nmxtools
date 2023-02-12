#!/usr/bin/env python3
#Check mseed data for internal format errors and gaps
# G. Helffrich/UB
#   3 Jan. 2015, 30 Aug. 2018, 4 Feb. 2023

import sys
from os import path
import glob
import warnings
from obspy import read
from obspy.io.mseed.util import get_record_information

def usage():
   print("usage: %s <opts> <file pattern> ..." % sys.argv[0])
   print("where <opts> is one or more of:")
   print('  -v - verbose output (summarizes each file contents)')
   print('  -f xn - fix any incorrect Steim-1 xn values in each file')
   print('  -g <file> - write gap report to <file>')
   print("  -h - print usage")
   print("enclose <file pattern> in primes or quotes to prevent expansion on")
   print("command line")
   return True

def plural(v):
   return '' if v == 1 else 's'

overb, ofix = False, False
use, iskip, gf, pat, tol = False, 0, None, (), 0.1
for i in range(1, len(sys.argv)):
   if i <= iskip: continue
   arg = sys.argv[i]
   if arg[0] == '-':                   ## Parse option
      if arg == '-h': use = usage()
      elif arg == '-v': overb = True
      elif arg == '-f':
         if i<len(sys.argv) and sys.argv[i+1] == "xn":
            arg = sys.argv[i+1]
            iskip = i+1
         else:
            arg = '(missing)'
         if arg == "xn":
            ofix = True
         else:
            print('**%s:  Bad -f arg "%s", ignored' % (sys.argv[0],arg))
      elif arg == '-t':
         if i<len(sys.argv):
            try:
               tol = float(sys.argv[i+1])
            except:
               arg = sys.argv[i+1]
               tol = None
            iskip = i+1
         else:
            arg = '(missing)'
            tol = None
         if tol is None:
            print('**%s:  Bad -t arg "%s", ignored' % (sys.argv[0],arg))
      elif arg == '-g':
         if i<len(sys.argv):
            gf = sys.argv[i+1]
            iskip = i+1
         else:
            print('**%s:  Missing -g arg, ignored' % (sys.argv[0]))
      else:
         print('**%s:  Bad arg "%s", ignored' % (sys.argv[0],arg))
         if not use: use = usage()
   else:
      pat += (arg,)

if len(pat) < 1:
   if not use: use = usage()
   sys.exit()

if gf is not None:
   gapf = open(gf, 'w')

with warnings.catch_warnings(record=True) as w:
   n, nw, ng, no = 0, 0, 0, 0
   etlf = None                                 # end time of last file
   for p in pat:
      for f in glob.glob(p):
         try:
            st = read(f,format="MSEED")
         except:
            print("%s: MSEED undecodeable" % (f))
            nw += 1
            continue
         fn = path.basename(f)
         if w is not None and len(w)>0:
            nw += 1
            print("%s: format error: %s" % (fn,w[-1].message))
            del w[-1]
         if len(st)>0 and etlf is not None:
            sttf = st[0].stats.starttime       # start time of this file
            si = st[0].stats.delta
            diff = etlf + si - sttf
            if diff < 0 and abs(diff) > tol*si:
               print("%s: %.4f s gap from %s" % (fn,-diff,fnlf))
               if gf is not None:
                  gapf.write("%s %.4f\n" % (fflf,-diff))
               ng += 1
            if diff > 0 and diff > tol*si:
               print("%s: %.4f s overlap with %s" % (fn,diff,fnlf))
               if gf is not None:
                  gapf.write("%s %.4f\n" % (fflf,-diff))
               no += 1
         if len(st)>0:
            info = get_record_information(f)
            rl, siz  = info['record_length'], info['filesize']
            etlf = get_record_information(f, offset=siz-rl)['endtime']
            fnlf = fn
            fflf = f
         if len(st)>1:
            print("%s: %d data gap%s" % \
                  (fn,len(st)-1,['','s'][min(1,len(st)-2)]))
            ng += len(st)-1
         if overb: print(st)
         n = n + 1

print('%d file%s checked, %d error%s, %d gap%s, %d overlap%s' % \
   (n, plural(n), nw, plural(nw), ng, plural(ng), no, plural(no)))
