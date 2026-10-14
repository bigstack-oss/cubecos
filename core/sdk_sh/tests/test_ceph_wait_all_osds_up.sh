#!/bin/bash
#
# Unit test for ceph_wait_all_osds_up in ../modules/sdk_ceph.sh: it returns once
# every OSD is up and stable, stops waiting when the up count has not grown for
# 5 min (one OSD that never returns), and its bound is wall clock, not a count
# of sleeps. Fakes ceph and the clock (sleep advances SECONDS); needs no cluster.
#   Run: bash test_ceph_wait_all_osds_up.sh
#
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$DIR/../modules/sdk_ceph.sh"
eval "$(awk '/^ceph_wait_all_osds_up\(\)/ {f=1} f{print} f&&/^}/{exit}' "$SRC")"
[ "$(type -t ceph_wait_all_osds_up)" = function ] || { echo "FAIL: function not extracted"; exit 1; }

FAILS=0
CEPH=fake_ceph
log_warning() { WARNED=1; }
fake_ceph() { echo "{\"osdmap\":{\"num_osds\":$TOTAL,\"num_up_osds\":$(up_now)}}"; }
# fake_ceph runs in $(...), so its cost is charged here: each pass = sleep + a 3s ceph status
sleep() { SECONDS=$((SECONDS + $1 + 3)); }
check() { if [ "$2" = "$3" ] ; then echo "ok   $1" ; else echo "FAIL $1: got $2 want $3" ; FAILS=$((FAILS+1)) ; fi ; }

# 1: all up from the start -> returns after ~60s of stability
TOTAL=12; up_now() { echo 12; }; WARNED=0; SECONDS=0
ceph_wait_all_osds_up 1800; check "all up returns quickly" $([ $SECONDS -lt 120 ] && echo yes || echo no) yes

# 2: one OSD never returns -> stops ~5 min after the last change, warns
TOTAL=12; up_now() { echo 11; }; WARNED=0; SECONDS=0
ceph_wait_all_osds_up 1800; check "dead OSD stops by no-progress" $([ $SECONDS -ge 300 ] && [ $SECONDS -lt 330 ] && echo yes || echo no) yes
check "dead OSD warns" $WARNED 1

# 3: OSDs come up slowly (one every 4 min) -> each change resets the 5-min window
TOTAL=12; up_now() { echo $(( 8 + SECONDS / 240 > 12 ? 12 : 8 + SECONDS / 240 )); }; WARNED=0; SECONDS=0
ceph_wait_all_osds_up 1800; check "slow OSDs are waited for" $([ $SECONDS -ge 960 ] && echo yes || echo no) yes
check "slow OSDs do not warn" $WARNED 0

# 4: the bound is wall clock -> a 600s bound with a flapping count ends near 600s
TOTAL=12; up_now() { echo $(( (SECONDS / 8) % 2 ? 10 : 11 )); }; WARNED=0; SECONDS=0
ceph_wait_all_osds_up 600; check "wall-clock bound" $([ $SECONDS -ge 600 ] && [ $SECONDS -lt 620 ] && echo yes || echo no) yes

[ $FAILS -eq 0 ] && echo "PASS" || { echo "$FAILS FAILED"; exit 1; }
