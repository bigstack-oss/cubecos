#!/bin/bash
#
# Unit test for ceph_osd_safe_remove() and ceph_osd_remove_disk_cleanup() in
# ../modules/sdk_ceph.sh -- the give-up logic while drained OSDs wait for
# `ceph osd safe-to-destroy`. It must
# 1. never queue a job that sleeps inside the every-minute runner,
# 2. keep waiting while recovery moves data (objects falling or bytes flowing),
#    even when the pg count stays the same,
# 3. give up only after 5 readings in a row with no progress at all,
# 4. on give-up restore every OSD of the disk, purge none, and drop the disk's jobs,
# 5. purge all of the disk's OSDs together once safe-to-destroy passes.
#
# Self-contained: extracts only the functions and stubs ceph / hex_sdk / cron.
# Run:  bash test_ceph_osd_safe_remove_stall.sh   (exit 0 = pass)
#
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$DIR/../modules/sdk_ceph.sh"

for f in ceph_osd_safe_remove ceph_osd_remove_disk_cleanup ; do
    fn="$(awk -v f="$f()" '$0 == f{p=1} p{print} p&&/^}/{exit}' "$SRC")"
    [ -n "$fn" ] || { echo "FAIL: $f not found in $SRC"; exit 1; }
    eval "$fn"
done

T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
QUEUE=$T/queue; LOG=$T/log; PURGED=$T/purged; RESTORED=$T/restored; DELETED=$T/deleted; STD=$T/std

# --- stubs ---------------------------------------------------------------
PGS=""                      # what safe-to-destroy reports this round ("" = safe, "nostats" = EAGAIN)
OBJ=0; RATE=0; HEALTH=HEALTH_WARN   # what ceph -s reports this round
DEAD_UP=0; DEAD_PGS=0       # what osd dump / osd df say about the OSD in the nostats case
IN=0                        # the .in of every OSD in osd dump
_hex_function() {           # _hex_function out err cmd... ; sets the named vars
    local -n _o=$1 _e=$2; shift 2
    echo "$*" >> $STD
    if [ -z "$PGS" ]; then _o="OSD(s) 10 are safe to destroy"; _e=""; return 0; fi
    if [ "$PGS" = nostats ]; then _o=""; _e="Error EAGAIN: OSD(s) 10 have no reported stats, and not all PGs are active+clean; we cannot draw any conclusions."; return 1; fi
    _o=""; _e="Error EBUSY: OSD(s) 10 have $PGS pgs currently mapped to them."; return 1
}
ceph_stub() {
    case "$*" in
        "-s -f json")        echo "{\"health\":{\"status\":\"$HEALTH\"},\"pgmap\":{\"misplaced_objects\":$OBJ,\"recovering_bytes_per_sec\":$RATE}}" ;;
        "osd dump -f json")  echo "{\"osds\":[{\"osd\":10,\"up\":$DEAD_UP,\"in\":$IN},{\"osd\":4,\"up\":$DEAD_UP,\"in\":$IN},{\"osd\":5,\"up\":$DEAD_UP,\"in\":$IN}]}" ;;
        "osd df osd."*" -f json") id=${3#osd.}; echo "{\"nodes\":[{\"id\":$id,\"pgs\":$DEAD_PGS}]}" ;;
        *"osd in"*|*"crush reweight"*) echo "$*" >> $RESTORED ;;
    esac
}
CEPH=ceph_stub
hexsdk_stub() {             # $HEX_SDK util_cron_add_every_minute_job <job> <feature>
    case "$1" in
        util_cron_add_every_minute_job) echo "$2" > $QUEUE ;;
        util_cron_delete_every_minute_job) echo "$2" >> $DELETED ;;
    esac
}
HEX_SDK=hexsdk_stub
systemctl() { echo "systemctl $*" >> $RESTORED; }
Quiet() { "$@" >/dev/null 2>&1; }
log_info() { echo "$1" >> $LOG; }
log_error() { echo "$1" >> $LOG; }
ceph_osd_purge() { echo "$1" >> $PURGED; }
ceph_osd_get_ids() { echo 4 5; }
WAITING=""                  # PGs ceph_osd_pgs_waiting_on reports
ceph_osd_pgs_waiting_on() { echo "$*" >> $T/waited; echo -n "$WAITING"; }
ceph_osd_is_osd_purged() { return 1; }
command -v jq >/dev/null || { echo "SKIP: jq not installed"; exit 0; }

pass=0 fail=0
ok()   { pass=$((pass+1)); }
bad()  { fail=$((fail+1)); echo "FAIL: $*"; }

# run one round with the queued job's arguments: pg count $1, objects $2, recovery B/s $3
FIRST=(10 0.21790 1 "")
round() {
    PGS=${1:-}; OBJ=${2:-0}; RATE=${3:-0}
    : > $QUEUE
    if [ -s $T/next ]; then
        # queued job is: <hexsdk> ceph_osd_safe_remove "<ids>" "<w>" "<n>" "<reading>" "<stalled>" "<dev>"
        eval "set -- $(sed 's/^[^ ]* ceph_osd_safe_remove //' $T/next)"
        ceph_osd_safe_remove "$@" >/dev/null 2>&1
    else
        ceph_osd_safe_remove "${FIRST[@]}" >/dev/null 2>&1
    fi
    cp $QUEUE $T/next 2>/dev/null || : > $T/next
}
reset() {
    : > $QUEUE; : > $LOG; : > $PURGED; : > $RESTORED; : > $T/next; : > $DELETED; : > $STD
    FIRST=(10 0.21790 1 ""); HEALTH=HEALTH_WARN; IN=0
}

# 1. a healthy drain: counts fall, then safe-to-destroy passes -> purge, no restore
reset
for c in "229 9000" "43 3000" "22 900" "7 100" "3 20" ""; do round $c; done
[ -s $PURGED ] && ok || bad "draining OSD was not purged when safe-to-destroy passed"
[ -s $RESTORED ] && bad "draining OSD was restored" || ok
grep -q "sleep" $T/next $QUEUE 2>/dev/null && bad "a queued job sleeps inside the runner" || ok

# 2. slow but moving: pg count stuck at 2 while objects fall -> never restored (the r730 case)
reset
round 2 900
for o in 800 700 600 500 400 300 200 100 50; do round 2 $o; done
[ -s $RESTORED ] && bad "slow drain with falling objects was restored" || ok
[ -s $T/next ] && ok || bad "no retry queued during a slow drain"

# 3. same pg and object counts but recovery bytes flowing -> progress, not a stall
reset
for i in 1 2 3 4 5 6 7 8; do round 2 70 1048576; done
[ -s $RESTORED ] && bad "drain with recovery bytes flowing was restored" || ok

# 4. nothing moves: 5 readings without progress are tolerated, the 6th gives up
reset
for i in 1 2 3 4 5; do round 7 70 0; done
[ -s $RESTORED ] && bad "gave up before 5 readings without progress" || ok
[ -s $T/next ] && ok || bad "no retry queued while waiting out the stall"
round 7 70 0
[ -s $RESTORED ] && ok || bad "did not give up after 5 readings without progress"
grep -q "could not be moved" $LOG && ok || bad "stall reason not logged"
[ -s $PURGED ] && bad "purged an OSD while giving up" || ok

# 5. progress in between resets the stall counter
reset
for i in 1 2 3 4 5; do round 7 70 0; done
round 7 60 0
for i in 1 2 3 4; do round 7 60 0; done
[ -s $RESTORED ] && bad "stall counter did not reset on progress" || ok

# 6. the queued job carries the reading and the stall counter forward
reset
round 9 80; round 9 80
grep -qE '"[0-9.]+" "[0-9]+" "9:80" "1" ""$' $T/next && ok || bad "reading/stall counter not passed to the next attempt: $(cat $T/next)"

# 7. a job queued by the old code ("<n> pgs" reading, no disk) still runs
reset
echo 'hexsdk_stub ceph_osd_safe_remove "10" "0.21790" "4" "7 pgs" "1"' > $T/next
round 7 70
grep -qE '"10" "0.21790" "5" "7:70" "0" ""$' $T/next && ok || bad "old-format job not continued: $(cat $T/next)"

# 8. a two-OSD disk: both checked together, both purged together
reset; FIRST=("4 5" "3.63869 3.63869" 1 "" 0 /dev/sdd)
round 3 50; round ""
grep -q "safe-to-destroy osd.4 osd.5" $STD && ok || bad "safe-to-destroy not asked for both OSDs: $(head -1 $STD)"
[ "$(tr '\n' ' ' < $PURGED)" = "4 5 " ] && ok || bad "both OSDs of the disk not purged: $(cat $PURGED)"

# 9. a two-OSD disk that stalls: restore BOTH, purge none, drop the disk's jobs
reset; FIRST=("4 5" "3.63869 1.81940" 1 "" 0 /dev/sdd)
for i in 1 2 3 4 5 6; do round 2 70 0; done
grep -q "crush reweight osd.4 3.63869" $RESTORED && grep -q "crush reweight osd.5 1.81940" $RESTORED \
    && ok || bad "crush weights of both OSDs not restored: $(cat $RESTORED)"
grep -q "osd in 4" $RESTORED && grep -q "osd in 5" $RESTORED && ok || bad "both OSDs not marked in"
grep -q "restart ceph-osd@4" $RESTORED && grep -q "restart ceph-osd@5" $RESTORED && ok || bad "both OSDs not restarted"
[ -s $PURGED ] && bad "purged an OSD of a disk being restored: $(cat $PURGED)" || ok
[ -s $T/next ] && bad "a safe_remove job is still queued after giving up" || ok
grep -qF 'ceph_osd_remove_disk_cleanup "/dev/sdd" ' $DELETED && ok || bad "disk cleanup job not dropped"

# 10. HEALTH_ERR and the time limit give up disk-wide too
reset; FIRST=("4 5" "3.6 3.6" 1 "" 0 /dev/sdd); HEALTH=HEALTH_ERR
round 9 900 100
[ -s $RESTORED ] && bad "HEALTH_ERR gave up on the first check" || ok
round 8 800 100
grep -q "osd in 4" $RESTORED && grep -q "osd in 5" $RESTORED && ok || bad "HEALTH_ERR did not restore both OSDs"
reset; FIRST=("4 5" "3.6 3.6" 30 "" 0 /dev/sdd)
round 9 900 100
grep -q "osd in 4" $RESTORED && grep -q "osd in 5" $RESTORED && ok || bad "time limit did not restore both OSDs"
grep -q "timed out" $LOG && ok || bad "time limit reason not logged"
[ -s $PURGED ] && bad "purged after the time limit" || ok

# 11. a long-dead OSD: no stats, down, nothing mapped -> purge at once, no stall clock
reset; DEAD_UP=0; DEAD_PGS=0
round nostats
[ -s $PURGED ] && ok || bad "dead OSD with nothing mapped was not purged"
[ -s $RESTORED ] && bad "dead OSD was restored" || ok

# 12. no stats but pgs still mapped, or the OSD is up -> keep waiting, never purge blind
reset; DEAD_UP=0; DEAD_PGS=12
round nostats
[ -s $PURGED ] && bad "purged an OSD that still has pgs mapped" || ok
[ -s $T/next ] && ok || bad "no retry queued while pgs are still mapped"
reset; DEAD_UP=1; DEAD_PGS=0
round nostats
[ -s $PURGED ] && bad "purged an OSD that is still up" || ok
DEAD_UP=0; DEAD_PGS=0
# ... or a PG waits on one of the disk's OSDs for its latest copy (#2157)
reset; WAITING=5.9; : > $T/waited; FIRST=("4 5" "3.6 3.6" 1 "" 0 /dev/sdd)
round nostats
[ -s $PURGED ] && bad "purged dead OSDs a PG still waits on" || ok
grep -qx "4 5" $T/waited && ok || bad "waiting-on not asked for the whole disk: $(cat $T/waited)"
WAITING=""

# 13. the disk cleanup stops, without requeueing, once an OSD of the disk is back in
reset; IN=1
ceph_osd_remove_disk_cleanup /dev/sdd 5 >/dev/null 2>&1 && bad "cleanup succeeded on a restored disk" || ok
[ -s $QUEUE ] && bad "cleanup requeued itself on a restored disk" || ok
reset; IN=0
ceph_osd_remove_disk_cleanup /dev/sdd 5 >/dev/null 2>&1
grep -qF 'ceph_osd_remove_disk_cleanup "/dev/sdd" "6"' $QUEUE && ok || bad "cleanup did not requeue while the OSDs drain"

echo "----"
echo "PASS=$pass FAIL=$fail"
[ "$fail" -eq 0 ] && { echo "OK: ceph_osd_safe_remove stall logic"; exit 0; } || exit 1
