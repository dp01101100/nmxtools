#/bin/sh
#   Shell script to drop a list of blocks from an input file
#
#   Usage:  dropblock.sh <file> [-b n] m ...
#     where <file> is the input file
#       -b n - sets alternate block size (512 default)
#       m ... - list of block numbers to drop
#
#   New file is written to standard output
fn=${1:-/dev/null}

# Set block size
[ "$2" == '-b' ] && ( bs=$3 ; shift 2 ; shift 2 ) || bs=512 ; shift 

dd bs=${bs} if=${fn} count=$(( $1 - 1 ))            # copy 1-(m-1)
cb=$1 ; shift
for i in $@ ; do
   dd bs=${bs} if=${fn} skip=${cb} count=$(( $i - $cb - 1 )) ; cb=$i
done
dd bs=${bs} if=${fn} skip=${cb}
