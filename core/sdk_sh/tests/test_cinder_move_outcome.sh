#!/bin/bash
#
# Unit test for cinder_move_outcome (../modules/sdk_cinder.sh), which the CLI's
# `iaas volume move` reads after dispatching the retype (#2100): a retype the
# scheduler drops (NoValidBackend) puts the volume back on its old type and
# must read as failed, not as the 202 the request got. The wait is bounded by
# wall clock. openstack and the clock are faked; needs no cluster.
#   Run: bash test_cinder_move_outcome.sh
#
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$DIR/../modules/sdk_cinder.sh"
eval "$(awk '/^cinder_move_outcome\(\)/ {f=1} f{print} f&&/^}/{exit}' "$SRC")"
[ "$(type -t cinder_move_outcome)" = function ] || { echo "FAIL: function not extracted"; exit 1; }

pass=0 fail=0
chk() { if [ "$2" = "$3" ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL: $1: got [$2] want [$3]"; fi; }

sleep() { SECONDS=$((SECONDS + $1 + 2)); }
vol() { printf '{"status":"%s","type":"%s","os-vol-host-attr:host":"%s","migration_status":%s}' "$1" "$2" "$3" "$4"; }
volume() { :; }
fake_os() { [ "$1 $2" = "volume show" ] && volume; }
OPENSTACK=fake_os
field() { echo "$OUT" | jq -r ".$1"; }

# 1: scheduler found no backend -> back to available on the old type
volume() { [ $SECONDS -lt 6 ] && vol retyping CubeStorage cube@ceph#ceph null || vol available CubeStorage cube@ceph#ceph null; }
SECONDS=0
OUT="$(cinder_move_outcome v1 qatier 60)"; RC=$?
chk "1 failed" "$(field state)" failed
chk "1 non-zero" "$RC" 1
chk "1 still on the old type" "$(field type)" CubeStorage

# 2: retype done -> new type and host
volume() { [ $SECONDS -lt 4 ] && vol retyping CubeStorage cube@ceph#ceph '"migrating"' || vol in-use qatier cube@qatier#qatier '"success"'; }
SECONDS=0
OUT="$(cinder_move_outcome v1 qatier 60)"; RC=$?
chk "2 done" "$(field state)" done
chk "2 zero" "$RC" 0
chk "2 new host" "$(field host)" "cube@qatier#qatier"

# 3: a long copy -> in progress at the bound, not failed
volume() { vol retyping CubeStorage cube@ceph#ceph '"migrating"'; }
SECONDS=0
OUT="$(cinder_move_outcome v1 qatier 60; echo " t=$SECONDS")"
T=${OUT##*t=}; OUT=${OUT% t=*}
chk "3 in progress" "$(field state)" in_progress
chk "3 migration status" "$(field migration_status)" migrating
chk "3 bounded by ~60s" "$([ "$T" -ge 60 ] && [ "$T" -lt 70 ] && echo yes || echo "no ($T)")" yes

# 4: the volume cannot be read -> unknown, not failed
volume() { return 1; }
SECONDS=0
OUT="$(cinder_move_outcome v1 qatier 10)"; RC=$?
chk "4 unknown" "$(field state)" unknown
chk "4 zero" "$RC" 0

echo "pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
