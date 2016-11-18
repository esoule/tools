#!/sbin/busybox ash
set -x
: ____________________________________________________________

./scripts/build.sh
: _____________________________________ expect help screen


./scripts/build.sh -h
: _____________________________________ expect help screen


./scripts/build.sh -q
: _____________________________________ expect illegal option


./scripts/build.sh -v  -l -z -a "" -a "FBB" -a " FAA " -b " ,,VNN,VMM, " -b VOO -b "" component13 '' " component12 " component11
: ________________________________ expect invalid empty values

FAMILY=ZZZENV VARIANT=QQQENV ./scripts/build.sh -v  -l -z -a "FBB" -a " FAA " -b " ,,VNN,VMM,all-variants " -b VOO -b "" component13 'all-components' " component12 " component11
: ________________________________ expect all-variants all-comp

FAMILY='  ZZZ ENV  ' VARIANT='  QQQ ENV  ' ./scripts/build.sh -v  -l -z   component13 'all-components' " component12 " component11
: ________________________________ expect environment usage

: ____________________________________________________________
