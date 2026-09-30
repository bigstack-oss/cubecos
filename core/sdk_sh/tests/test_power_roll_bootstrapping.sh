#!/bin/bash
#
# Unit test for the rolling "bootstrapping" inference in ../modules/sdk_power.sh
# (#710). A node that is still up on its old kernel answers ping, so the inflight
# "rebooting" node may only be reported as bootstrapping once it answers from a
# kernel booted after its reboot was stamped.
#
# Self-contained: extracts _power_roll_booted_since and power_roll_status_json,
# mocks ssh, and feeds a hand-written job.json.  Run: bash test_...sh
#
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$DIR/../modules/sdk_power.sh"

for fn in _power_roll_booted_since power_roll_status_json ; do
    body="$(awk -v f="^${fn}\\\\(\\\\)" '$0~f{p=1} p{print} p&&/^}/{exit}' "$SRC")"
    [ -n "$body" ] || { echo "FAIL: $fn not extracted"; exit 1; }
    eval "$body"
done

pass=0 fail=0
chk(){ if [ "$2" = "$3" ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL: $1: got [$2] want [$3]"; fi; }

# ssh prints the node's kernel boot time, or fails when it is down
BTIME=
ssh(){ [ -n "$BTIME" ] || return 255 ; echo "$BTIME" ; }
timeout(){ shift ; "$@" ; }

ROLLING_JOB=$(mktemp)
cat > "$ROLLING_JOB" <<'EOF'
{"state":"running","inflight":"c1","nodes":[
 {"hostname":"c1","ip":"10.0.0.1","status":"rebooting","phase_ts":{"rebooting":1000}},
 {"hostname":"c2","ip":"10.0.0.2","status":"pending"}]}
EOF
phase(){ power_roll_status_json | jq -r --arg h "$1" '.progresses[]|select(.host==$h)|.phase' ; }

# 1. helper
BTIME=900  ; _power_roll_booted_since 10.0.0.1 1000 ; chk "1 old kernel"  "$?" "1"
BTIME=1100 ; _power_roll_booted_since 10.0.0.1 1000 ; chk "1 new kernel"  "$?" "0"
BTIME=     ; _power_roll_booted_since 10.0.0.1 1000 ; chk "1 down"        "$?" "1"
BTIME=1100 ; _power_roll_booted_since 10.0.0.1 0    ; chk "1 no stamp"    "$?" "1"
BTIME=1100 ; _power_roll_booted_since ""       1000 ; chk "1 no ip"       "$?" "1"

# 2. status json: still answering from the old kernel -> rebooting, not bootstrapping
BTIME=900  ; chk "2 old kernel"   "$(phase c1)" "rebooting"
BTIME=     ; chk "2 down"         "$(phase c1)" "rebooting"
BTIME=1100 ; chk "2 back up"      "$(phase c1)" "bootstrapping"
BTIME=1100 ; chk "2 peer pending" "$(phase c2)" "pending"

rm -f "$ROLLING_JOB"
echo "----" ; echo "PASS=$pass FAIL=$fail"
[ "$fail" -eq 0 ] && { echo "OK: roll bootstrapping inference" ; exit 0 ; } || exit 1
