#!/bin/bash
#
# Unit test for _diagSrvShiftHost in ../modules/sdk_diagnostics.sh (cubecos#1727): the
# migration round of `diagnostics testground construct`, which live-migrates every
# _diagnostics VM to the next compute node and then reports each one as migrated or not.
#
# The regression that matters: the wait was `for i in {1..10}` around `server list` with
# no delay, so it gave up after ten back-to-back API calls. A migration still running by
# then was reported "Failed to migrate", and the report then skipped the rest of that
# host's VMs. The round also returned 0 whatever it reported. It must wait while nova
# shows MIGRATING, against a deadline, judge each VM by where it landed, and fail the
# round when any VM did not land.
#
# Self-contained: sources the module (see test_diagnostics_cirros_host_exec.sh) and stubs
# openstack, nova, cubectl and sleep, so it needs no cluster. sleep advances bash's
# SECONDS, so the waits run on a fake clock and take no time.
#   Run: bash test_diagnostics_srv_shift_host.sh   (exit 0 = pass)
#   SRC=<other sdk_diagnostics.sh> runs the same assertions against another version, e.g.
#   origin/develop before #1727, where the cases marked [#1727] must fail.
#
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="${SRC:-$DIR/../modules/sdk_diagnostics.sh}"

PROG=test source "$SRC" || { echo "FAIL: cannot source $SRC"; exit 1; }
[ "$(type -t _diagSrvShiftHost)" = function ] || { echo "FAIL: _diagSrvShiftHost not found in $SRC"; exit 1; }

pass=0 fail=0
ok()  { pass=$((pass+1)); }
bad() { fail=$((fail+1)); echo "FAIL: $1"; }
check() { if [ "$2" = "$3" ]; then ok; else bad "$1: got '$2', want '$3'"; fi; }
has()   { if grep -qF -- "$3" "$2"; then ok; else bad "$1: no line matching '$3'"; fi; }
hasnt() { if grep -qF -- "$3" "$2"; then bad "$1: unexpected line matching '$3'"; else ok; fi; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
CALLS=$TMP/calls
OUT=$TMP/out

# ---- stubs ---------------------------------------------------------------
OPENSTACK=fake_openstack

# SERVERS: ids in list order. HOME[id]: the compute it starts on. OUTCOME[id]: what its
# migration does -- "land" on the destination or "rollback" to HOME after DUR[id] seconds,
# or "hang" in MIGRATING. TO and DONE_AT are filled in when the migration is requested.
declare -A HOME OUTCOME DUR TO DONE_AT
state() {   # "<status> <host>" of server $1 at the current SECONDS
    local s=$1 host=${HOME[$1]}
    if [ -z "${DONE_AT[$s]:-}" ] ; then echo "ACTIVE $host" ; return ; fi
    if [ "${OUTCOME[$s]}" = hang ] || [ $SECONDS -lt ${DONE_AT[$s]} ] ; then echo "MIGRATING $host" ; return ; fi
    [ "${OUTCOME[$s]}" = rollback ] || host=${TO[$s]}
    echo "ACTIVE $host"
}
fake_openstack() {
    echo "openstack $*" >> "$CALLS"
    local s st sep=
    case "$*" in
        "server list --project _diagnostics --long -f json")
            printf '['
            for s in $SERVERS ; do
                read -r st h <<<"$(state $s)"
                printf '%s{"ID": "%s", "Name": "vm-%s", "Status": "%s", "Host": "%s"}' "$sep" "$s" "$s" "$st" "$h"
                sep=', '
            done
            printf ']\n'
            ;;
        "server show "*" -f json")
            read -r st h <<<"$(state $3)"
            printf '{"id": "%s", "name": "vm-%s", "status": "%s", "OS-EXT-SRV-ATTR:host": "%s"}\n' "$3" "$3" "$st" "$h"
            ;;
        "--os-compute-api-version 2.30 server migrate --live-migration --host "*)
            TO[$8]=$7
            DONE_AT[$8]=$((SECONDS + ${DUR[$8]}))
            ;;
    esac
}
nova() { echo "nova $*" >> "$CALLS" ; }
cubectl() { echo '[{"hostname": "cmp1"}, {"hostname": "cmp2"}]' ; }
sleep() { SECONDS=$((SECONDS + $1)) ; }

# run_shift: one migration round, from a clean clock. Not in a subshell: the migration
# stubs record into the arrays above, and the fake clock lives in this shell.
run_shift() {
    : > "$CALLS"
    TO=() DONE_AT=()
    SECONDS=0
    set +u                      # as hex_sdk runs it
    _diagSrvShiftHost >"$OUT" 2>&1
    RC=$?
    set -u
    END=$SECONDS
}

# ---- 1. [#1727] migrations that take a while are waited for --------------
SERVERS="s1 s2"
HOME=([s1]=cmp1 [s2]=cmp2) OUTCOME=([s1]=land [s2]=land) DUR=([s1]=40 [s2]=20)
run_shift
check "1 [#1727] rc" "$RC" 0
has   "1 s1 sent to the next compute" "$CALLS" "openstack --os-compute-api-version 2.30 server migrate --live-migration --host cmp2 s1"
has   "1 s2 sent round to the first" "$CALLS" "openstack --os-compute-api-version 2.30 server migrate --live-migration --host cmp1 s2"
hasnt "1 not through the deprecated nova cli" "$CALLS" "nova "
has   "1 [#1727] s1 reported migrated" "$OUT" "Migrated VM from cmp1 to cmp2: vm-s1 (s1)"
has   "1 [#1727] s2 reported migrated" "$OUT" "Migrated VM from cmp2 to cmp1: vm-s2 (s2)"
hasnt "1 [#1727] no false failure" "$OUT" "Failed to migrate"

# ---- 2. [#1727] a rolled-back migration fails the round, without the full wait ----
SERVERS="s1 s2"
HOME=([s1]=cmp1 [s2]=cmp2) OUTCOME=([s1]=rollback [s2]=land) DUR=([s1]=15 [s2]=15)
run_shift
if [ "$RC" != 0 ] ; then ok ; else bad "2 [#1727] a failed migration must fail the round, got rc=0" ; fi
has   "2 failure reported" "$OUT" "Failed to migrate VM from cmp1 to cmp2: vm-s1 (s1)"
has   "2 the other VM still reported" "$OUT" "Migrated VM from cmp2 to cmp1: vm-s2 (s2)"
if [ $END -lt 120 ] ; then ok ; else bad "2 [#1727] a rollback is seen when nova reports it, not at the deadline (took ${END}s)" ; fi

# ---- 3. [#1727] one failure does not hide the next VM on the same host ----
SERVERS="s1 s3 s2"
HOME=([s1]=cmp1 [s3]=cmp1 [s2]=cmp2) OUTCOME=([s1]=rollback [s3]=land [s2]=land) DUR=([s1]=5 [s3]=5 [s2]=5)
run_shift
if [ "$RC" != 0 ] ; then ok ; else bad "3 [#1727] round with a failed VM must fail, got rc=0" ; fi
has   "3 first VM on cmp1 failed" "$OUT" "Failed to migrate VM from cmp1 to cmp2: vm-s1 (s1)"
has   "3 [#1727] second VM on cmp1 still judged" "$OUT" "Migrated VM from cmp1 to cmp2: vm-s3 (s3)"

# ---- 4. [#1727] a migration that never ends is cut off at the deadline ----
SERVERS="s1 s2"
HOME=([s1]=cmp1 [s2]=cmp2) OUTCOME=([s1]=hang [s2]=land) DUR=([s1]=0 [s2]=5)
run_shift
if [ "$RC" != 0 ] ; then ok ; else bad "4 [#1727] a hung migration must fail the round, got rc=0" ; fi
has   "4 hung VM reported" "$OUT" "Failed to migrate VM from cmp1 to cmp2: vm-s1 (s1)"
if [ $END -ge 300 ] ; then ok ; else bad "4 [#1727] waited until the deadline (took ${END}s)" ; fi
if [ $END -lt 400 ] ; then ok ; else bad "4 gave up near the deadline (took ${END}s)" ; fi

echo "pass=$pass fail=$fail"
[ "$fail" = 0 ]
