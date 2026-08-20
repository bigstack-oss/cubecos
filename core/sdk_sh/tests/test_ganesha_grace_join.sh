#!/bin/bash
#
# Unit test for ceph_ganesha_grace_join (../modules/sdk_ceph.sh) and the
# ceph_mds auto-repair that must use it (../modules/sdk_health.sh).
#
# ganesha's rados_cluster recovery backend exits fatally when the node is not a
# member of the grace DB ("Cluster membership check failed: -2"), so restarting
# the daemon can never recover that state -- the membership has to be restored
# first. Registration is bounded (`timeout 60 ganesha-rados-grace ... add`) so a
# RADOS stall cannot wedge the config commit, which means it can expire and
# leave the node unregistered; this is the path that repairs it.
#
# Self-contained: extracts the functions and mocks ganesha-rados-grace, timeout
# and the cmd layer, so it needs no cluster and no ceph.  Run: bash test_...sh
#
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

body="$(awk '/^ceph_ganesha_grace_join\(\)/{p=1} p{print} p&&/^}/{exit}' "$DIR/../modules/sdk_ceph.sh")"
[ -n "$body" ] || { echo "FAIL: ceph_ganesha_grace_join not extracted"; exit 1; }
eval "$body"
body="$(awk '/^_health_ceph_mds_auto_repair\(\)/{p=1} p{print} p&&/^}/{exit}' "$DIR/../modules/sdk_health.sh")"
[ -n "$body" ] || { echo "FAIL: _health_ceph_mds_auto_repair not extracted"; exit 1; }
eval "$body"

LOG=$(mktemp)
MEMBERS=$(mktemp)
pass=0 fail=0
chk(){ if [ "$2" = "$3" ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL: $1: got [$2] want [$3]"; fi; }
saw(){ grep -qe "$1" "$LOG" && echo y || echo n; }

# --- mocks
# grace DB: `dump` prints the member table, `add` appends unless ADD_BREAKS=1
ganesha-rados-grace(){
    local op="" pool=""
    while [ $# -gt 0 ]; do
        case "$1" in
            -p) pool=$2 ; shift 2 ;;
            dump) op=dump ; shift ;;
            add) op=add ; shift ; echo "grace add $1" >> "$LOG" ; [ "${ADD_BREAKS:-0}" = 1 ] || echo "$1" >> "$MEMBERS" ; shift ;;
            *) shift ;;
        esac
    done
    if [ "$op" = dump ] ; then
        echo "grace dump pool=$pool" >> "$LOG"
        echo "cur=1 rec=0"
        awk '{print $1"\t  "}' "$MEMBERS"
    fi
    return 0
}
timeout(){ shift ; "$@" ; }            # drop the duration, run the command
Quiet(){ [ "${1:-}" = "-n" ] && shift ; "$@" ; }
cmd(){ echo "cmd $*" >> "$LOG" ; }
HEX_SDK=hex_sdk
HOSTNAME=c1
GANESHA_CONF=$(mktemp)
printf 'NFSv4 {\n\tRecoveryBackend = rados_cluster;\n\tpool = "cephfs_data";\n\tnodeid = c1;\n}\n' > "$GANESHA_CONF"

# 1. already a member: verify only, never re-add
printf 'c1\nc2\nc3\n' > "$MEMBERS" ; : > "$LOG"
ceph_ganesha_grace_join ; rc=$?
chk "1 rc 0"            "$rc"                "0"
chk "1 no add needed"   "$(saw 'grace add')" "n"

# 2. missing: registers this node, then confirms it took
printf 'c2\nc3\n' > "$MEMBERS" ; : > "$LOG"
ceph_ganesha_grace_join ; rc=$?
chk "2 rc 0"                "$rc"                    "0"
chk "2 added self"          "$(saw 'grace add c1')"  "y"
chk "2 used the conf pool"  "$(saw 'pool=cephfs_data')" "y"
chk "2 member now"          "$(grep -cx c1 "$MEMBERS")" "1"

# 3. add silently does not take (the bounded-call-expired case): must report failure
printf 'c2\nc3\n' > "$MEMBERS" ; : > "$LOG" ; ADD_BREAKS=1
ceph_ganesha_grace_join ; rc=$?
chk "3 nonzero rc"      "$rc"                   "1"
chk "3 tried to add"    "$(saw 'grace add c1')" "y"
unset ADD_BREAKS

# 4. the ceph_mds auto-repair for a ganesha fault must restore membership, not
#    just bounce the daemon -- a bare restart cannot fix a missing member
for code in 3 4 5 ; do
    : > "$LOG" ; ERR_CODE=$code
    _health_ceph_mds_auto_repair
    chk "4 code $code joins grace"    "$(saw 'grace_join')"               "y"
    chk "4 code $code restarts after" "$(saw 'restart nfs-ganesha')"      "y"
done

# 5. unrelated codes keep their own remedies
: > "$LOG" ; ERR_CODE=1 ; _health_ceph_mds_auto_repair
chk "5 code 1 untouched" "$(saw 'grace_join')" "n"
: > "$LOG" ; ERR_CODE=2 ; _health_ceph_mds_auto_repair
chk "5 code 2 untouched" "$(saw 'grace_join')" "n"

rm -f "$LOG" "$MEMBERS" "$GANESHA_CONF" 2>/dev/null
echo "----" ; echo "PASS=$pass FAIL=$fail"
[ "$fail" -eq 0 ] && { echo "OK: ganesha grace join" ; exit 0 ; } || exit 1
