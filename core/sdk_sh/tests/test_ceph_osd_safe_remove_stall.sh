#!/bin/bash
#
# Unit test for ceph_osd_safe_remove() in ../modules/sdk_ceph.sh -- the give-up
# logic while a drained OSD waits for `ceph osd safe-to-destroy`. It must
# 1. never queue a job that sleeps inside the every-minute runner,
# 2. give up ("restore") only after the pg count has not moved for 3
#    consecutive readings, not because two readings happened to match,
# 3. purge as soon as safe-to-destroy passes.
#
# Self-contained: extracts only the function and stubs ceph / hex_sdk / cron.
# Run:  bash test_ceph_osd_safe_remove_stall.sh   (exit 0 = pass)
#
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$DIR/../modules/sdk_ceph.sh"

fn="$(awk '$0 == "ceph_osd_safe_remove()"{p=1} p{print} p&&/^}/{exit}' "$SRC")"
[ -n "$fn" ] || { echo "FAIL: ceph_osd_safe_remove not found in $SRC"; exit 1; }
eval "$fn"

T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
QUEUE=$T/queue; LOG=$T/log; PURGED=$T/purged; RESTORED=$T/restored

# --- stubs ---------------------------------------------------------------
PGS=""                      # what safe-to-destroy reports this round ("" = safe, "nostats" = EAGAIN)
DEAD_UP=0; DEAD_PGS=0       # what osd dump / osd df say about the OSD in the nostats case
_hex_function() {           # _hex_function out err cmd... ; sets the named vars
    local -n _o=$1 _e=$2; shift 2
    if [ -z "$PGS" ]; then _o="OSD(s) 10 are safe to destroy"; _e=""; return 0; fi
    if [ "$PGS" = nostats ]; then _o=""; _e="Error EAGAIN: OSD(s) 10 have no reported stats, and not all PGs are active+clean; we cannot draw any conclusions."; return 1; fi
    _o=""; _e="Error EBUSY: OSD(s) 10 have $PGS pgs currently mapped to them."; return 1
}
ceph_stub() {
    case "$*" in
        "-s -f json")        echo '{"health":{"status":"HEALTH_OK"}}' ;;
        "osd dump -f json")  echo "{\"osds\":[{\"osd\":10,\"up\":$DEAD_UP}]}" ;;
        "osd df osd.10 -f json") echo "{\"nodes\":[{\"id\":10,\"pgs\":$DEAD_PGS}]}" ;;
        *"osd in"*|*"crush reweight"*) echo "$*" >> $RESTORED ;;
    esac
}
CEPH=ceph_stub
hexsdk_stub() {             # $HEX_SDK util_cron_add_every_minute_job <job> <feature>
    case "$1" in
        util_cron_add_every_minute_job) echo "$2" > $QUEUE ;;
        util_cron_delete_every_minute_job) : ;;
    esac
}
HEX_SDK=hexsdk_stub
systemctl() { echo "systemctl $*" >> $RESTORED; }
Quiet() { "$@" >/dev/null 2>&1; }
log_info() { echo "$1" >> $LOG; }
log_error() { echo "$1" >> $LOG; }
ceph_osd_purge() { echo "$1" >> $PURGED; }
command -v jq >/dev/null || { echo "SKIP: jq not installed"; exit 0; }

pass=0 fail=0
ok()   { pass=$((pass+1)); }
bad()  { fail=$((fail+1)); echo "FAIL: $*"; }

# run one round with the queued job's arguments, feeding pg count $1
round() {
    PGS=$1
    : > $QUEUE
    if [ -s $T/next ]; then
        # queued job is: <hexsdk> ceph_osd_safe_remove "<id>" "<w>" "<n>" "<pgs>" "<stalled>"
        eval "set -- $(sed 's/^[^ ]* ceph_osd_safe_remove //' $T/next)"
        ceph_osd_safe_remove "$@" >/dev/null 2>&1
    else
        ceph_osd_safe_remove 10 0.21790 1 "" >/dev/null 2>&1
    fi
    cp $QUEUE $T/next 2>/dev/null || : > $T/next
}
reset() { : > $QUEUE; : > $LOG; : > $PURGED; : > $RESTORED; : > $T/next; }

# 1. a healthy drain: counts fall, then safe-to-destroy passes -> purge, no restore
reset
for c in "229 " "43 " "22 " "7 " "3 " ""; do round "${c% }"; done
[ -s $PURGED ] && ok || bad "draining OSD was not purged when safe-to-destroy passed"
[ -s $RESTORED ] && bad "draining OSD was restored" || ok
grep -q "sleep" $T/next $QUEUE 2>/dev/null && bad "a queued job sleeps inside the runner" || ok

# 2. two identical readings in a row (the overlap case) must NOT give up
reset
for c in 229 43 7 7; do round $c; done
[ -s $RESTORED ] && bad "gave up after only two identical readings" || ok
[ -s $T/next ] && ok || bad "no retry queued after two identical readings"
# ... and a third identical reading must
round 7
[ -s $RESTORED ] && ok || bad "did not give up after three identical readings"
grep -q "could not be moved" $LOG && ok || bad "stall reason not logged"

# 3. progress in between resets the stall counter
reset
for c in 50 7 7 6 6; do round $c; done
[ -s $RESTORED ] && bad "stall counter did not reset on progress" || ok
round 6
[ -s $RESTORED ] && ok || bad "did not give up after three identical readings following progress"

# 4. the queued job carries the stall counter forward
reset
round 9; round 9
grep -qE '"[0-9.]+" "[0-9]+" "9 pgs" "1"$' $T/next && ok || bad "stall counter not passed to the next attempt: $(cat $T/next)"

# 5. a long-dead OSD: no stats, down, nothing mapped -> purge at once, no stall clock
reset; DEAD_UP=0; DEAD_PGS=0
round nostats
[ -s $PURGED ] && ok || bad "dead OSD with nothing mapped was not purged"
[ -s $RESTORED ] && bad "dead OSD was restored" || ok

# 6. no stats but pgs still mapped, or the OSD is up -> keep waiting, never purge blind
reset; DEAD_UP=0; DEAD_PGS=12
round nostats
[ -s $PURGED ] && bad "purged an OSD that still has pgs mapped" || ok
[ -s $T/next ] && ok || bad "no retry queued while pgs are still mapped"
reset; DEAD_UP=1; DEAD_PGS=0
round nostats
[ -s $PURGED ] && bad "purged an OSD that is still up" || ok

echo "----"
echo "PASS=$pass FAIL=$fail"
[ "$fail" -eq 0 ] && { echo "OK: ceph_osd_safe_remove stall logic"; exit 0; } || exit 1
