#!/bin/bash
#
# ceph_osd_promote_disk / ceph_osd_demote_disk: they do not mark the OSDs out
# (#1488), and a recovery wait that runs out is reported (#1466).
#
# Both functions change a disk's device class and then wait for recovery in a
# `for i in {1..60}` loop with `sleep 10` -- a fixed 600 s.
#
# They used to mark the OSDs `out` first and bring them back `in` afterwards.
# Two defects came out of that pair, and removing it answers both:
#
#   #1466  the `osd in` sat INSIDE the wait loop, next to the break, so a
#          recovery that outlasted the ceiling never reached it: the OSDs stayed
#          `out`, and the function still returned 0. Nothing downstream could
#          tell that a promote had left the cluster a replica short.
#   #1488  the `osd out` cost more movement than it saved in every rule layout
#          measured -- on the cachepool's own rule it split one remapping into
#          two, which is what it was supposed to be preventing.
#
# So the assertions below are mostly about calls that must NOT happen. That only
# means something because the stub records them: a no-op stub could not tell the
# fix from a regression that puts the pair back.
#
# Self-contained: extracts the two functions, stubs ceph / hex_sdk / Quiet and
# -- critically -- `sleep`, so the 600 s timeout case runs instantly.
#   Run: bash test_ceph_promote_demote_disk.sh
#
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$DIR/../modules/sdk_ceph.sh"
for f in ceph_osd_promote_disk ceph_osd_demote_disk ; do
    eval "$(awk -v n="^$f\\\\(\\\\)" '$0 ~ n {f=1} f{print} f&&/^}/{exit}' "$SRC")"
    [ "$(type -t "$f")" = function ] || { echo "FAIL: $f not extracted"; exit 1; }
done

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# Real sleep would make the timeout case take ten minutes. Recording the calls
# also lets a test assert the loop ran to its ceiling rather than exiting early.
sleep() { echo "sleep $1" >> "$TMP/calls" ; }

# The real Quiet returns the command's status EXCEPT with -n, which forces 0.
Quiet() {
    if [ "${1:-}" = -n ] ; then shift; "$@" >/dev/null 2>&1; return 0; fi
    "$@" >/dev/null 2>&1
}
Error() { echo "Error: $*" >&2 ; return 1 ; }

# RECOVERING: what `ceph -s` reports for recovering_objects_per_sec.
#   "null"  -> nothing moving, the loop settles on the first pass
#   a number -> still moving, so the loop runs to its 600 s ceiling
RECOVERING=null
fake_ceph() {
    local cmd="$*"
    echo "ceph $cmd" >> "$TMP/calls"
    case "$cmd" in
        '-s -f json') echo "{\"health\":{\"status\":\"HEALTH_OK\"},\"pgmap\":{\"recovering_objects_per_sec\":$RECOVERING}}" ;;
        'osd crush class ls-osd '*) printf '0\n1\n2\n' ;;
    esac
    return 0
}
CEPH=fake_ceph

fake_sdk() {
    case "$1" in
        ceph_get_ids_by_dev) printf '3\n4\n' ;;
    esac
    return 0
}
HEX_SDK=fake_sdk

CLASS_NOW=hdd
ceph_osd_get_class() { echo "$CLASS_NOW" ; }
ceph_osd_test_cache() { echo off ; }
ceph_adjust_cache_flush_bytes() { echo "flush_adjusted" >> "$TMP/calls" ; return 0 ; }
BUILTIN_CACHEPOOL=cachepool

pass=0 fail=0
ck() { [ "$1" = "$2" ] && pass=$((pass+1)) || { fail=$((fail+1)); echo "FAIL: $3 -> got '$1' want '$2'"; }; }
ckhas() { case "$1" in *"$2"*) pass=$((pass+1));; *) fail=$((fail+1)); echo "FAIL: $3 -> output lacks '$2'";; esac; }

reset() { : > "$TMP/calls" ; CLASS_NOW=hdd ; }
in_calls() { grep -c "^ceph osd in " "$TMP/calls" | tr -d ' ' ; }
out_calls() { grep -c "^ceph osd out " "$TMP/calls" | tr -d ' ' ; }
sleeps()   { grep -c '^sleep ' "$TMP/calls" | tr -d ' ' ; }
# The class change is what has to keep happening once out/in are gone -- without
# these two, every assertion above would pass on a function that did nothing.
rmclass_calls()  { grep -c "^ceph osd crush rm-device-class " "$TMP/calls" | tr -d ' ' ; }
setclass_calls() { grep -c "^ceph osd crush set-device-class " "$TMP/calls" | tr -d ' ' ; }

# ---- 1a. promote, recovery settles ----
# The class change is the whole of the work: rm-device-class then
# set-device-class, on every OSD of the device, and nothing marked out.
reset
RECOVERING=null
OUT=$(ceph_osd_promote_disk /dev/sdb ssd 2>&1); RC=$?
ck "$RC" 0 "1a a settled promote succeeds"
ck "$(out_calls)" 0 "1a no OSD is marked out (#1488)"
ck "$(in_calls)" 0 "1a and none has to be brought back in"
ck "$(rmclass_calls)" 1 "1a the old class is removed"
ck "$(setclass_calls)" 1 "1a and the new one set -- the work still happens"
ckhas "$(cat "$TMP/calls")" "osd crush set-device-class ssd osd.3 osd.4" "1a on every OSD of the device"
ck "$(grep -c flush_adjusted "$TMP/calls" | tr -d ' ')" 1 "1a the cache flush size was adjusted"

# ---- 1b. promote, recovery outlasts the 600s ceiling ----
# #1466 was that this path skipped the `osd in` and still returned 0. With the
# pair gone there is no OSD left out to begin with -- but the caller asked for a
# settled cluster and did not get one, so it is still told.
reset
RECOVERING=12.5
OUT=$(ceph_osd_promote_disk /dev/sdb ssd 2>&1); RC=$?
ck "$RC" 1 "1b a promote whose recovery times out reports non-zero"
ck "$(out_calls)" 0 "1b nothing was marked out, so nothing can be left out"
ck "$(in_calls)" 0 "1b and there is no osd in to skip"
ckhas "$OUT" "class change is done" "1b says the change itself landed"
ckhas "$OUT" "continues in the background" "1b says recovery is not finished"
ck "$(sleeps)" 60 "1b the wait ran to its ceiling"
ck "$(setclass_calls)" 1 "1b the class change happened before the wait"

# ---- 1c/1d. demote is the same shape and gets the same treatment ----
reset
RECOVERING=null
CLASS_NOW=ssd
OUT=$(ceph_osd_demote_disk /dev/sdb hdd 2>&1); RC=$?
ck "$RC" 0 "1c a settled demote succeeds"
ck "$(out_calls)" 0 "1c marks nothing out"
ck "$(in_calls)" 0 "1c and brings nothing back in"
ck "$(setclass_calls)" 1 "1c the class change still happens"

reset
RECOVERING=12.5
CLASS_NOW=ssd
OUT=$(ceph_osd_demote_disk /dev/sdb hdd 2>&1); RC=$?
ck "$RC" 1 "1d a demote whose recovery times out reports non-zero"
ck "$(out_calls)" 0 "1d marks nothing out"
ck "$(in_calls)" 0 "1d and has no osd in to skip"

# ---- 1e. the early exits are untouched ----
reset
CLASS_NOW=ssd
OUT=$(ceph_osd_promote_disk /dev/sdb ssd 2>&1); RC=$?
ck "$RC" 0 "1e promoting a disk already in the target class is a no-op"
ck "$(out_calls)" 0 "1e and takes nothing out"

reset
OUT=$(ceph_osd_promote_disk "" ssd 2>&1); RC=$?
ck "$RC" 1 "1f an empty device is refused"
ck "$(out_calls)" 0 "1f and takes nothing out"

echo "----"; echo "PASS=$pass FAIL=$fail"
[ "$fail" -eq 0 ] && { echo "OK: promote/demote disk recovery wait"; exit 0; } || exit 1
