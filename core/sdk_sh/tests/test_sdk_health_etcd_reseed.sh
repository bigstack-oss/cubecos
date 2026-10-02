#!/bin/bash
#
# Unit test for the etcd member reseed in health_etcd_repair (../modules/sdk_health.sh).
#
# What is asserted: the reseed's `cubectl this-node reset && cubectl this-node join`
# runs on the member being reseeded, as one remote command -- it used to go through
# Quiet remote_run, whose eval split the && and ran the join on the repairing node;
# it waits for the third failed restart and for quorum without that member; and a
# member that cannot be reached is skipped instead of Erroring out of the repair, so
# the other members and the etcd-watch repair still get their turn.
#
# Self-contained: extracts health_etcd_repair and the etcd-watch helpers it calls,
# stubs cmd, is_sshable, is_remote_running, remote_systemd_restart, etcdctl and a
# local cubectl that must never run. No cluster, no SSH.
# Run:  bash test_sdk_health_etcd_reseed.sh   (exit 0 = pass)
#
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$DIR/../modules/sdk_health.sh"

PROG=test
source "$DIR/../modules/errcodes"

for f in health_etcd_repair _health_etcd_watch_scan _health_etcd_watch_repair ; do
    fn="$(awk -v want="^$f\\\\(\\\\)" '$0 ~ want {f=1} f{print} f&&/^}/{exit}' "$SRC")"
    [ -n "$fn" ] || { echo "FAIL: $f not found in $SRC"; exit 1; }
    eval "$fn"
done

pass=0 fail=0
ok()  { pass=$((pass+1)); }
bad() { fail=$((fail+1)); echo "FAIL: $1"; }

# The reseed counters live at a fixed /tmp path keyed by node name; use names no
# real node has, and clear them on the way out.
N1=t1336m1 N2=t1336m2 N3=t1336m3 P1=t1336p1
cntf() { echo "/tmp/health_etcd_${1}_reseed.count" ; }
trap 'rm -f $(cntf $N1) $(cntf $N2) $(cntf $N3)' EXIT

ETCD_HEALTHY=2
ETCDCTL=etcdctl_stub
etcdctl_stub() {
    case "$*" in
        "member list") seq 3 ;;
        "endpoint health --cluster") for _ in $(seq "$ETCD_HEALTHY") ; do echo "x is healthy" ; done ;;
        "get cluster. --prefix --keys-only -w json") echo '{"kvs":[{"mod_revision":100}]}' ;;
    esac
}

declare -A ETCD_UP REACH WATCH
is_remote_running() { [ "$2" = "etcd" ] && [ "${ETCD_UP[$1]:-1}" = "1" ]; }
is_sshable()        { [ "${REACH[$1]:-1}" = "1" ]; }
remote_systemd_restart() { RESTARTED+="$1 " ; }
cubectl()           { LOCAL_CUBECTL+="cubectl $* ; " ; }

# cmd -v answers the etcd-watch probe from WATCH (revision 999, never behind);
# cmd -n records the command and the node it was sent to.
cmd() {
    local verbose=0 nodes=() opt OPTIND=1 n
    while getopts "vn:" opt ; do
        case $opt in
            v) verbose=1 ;;
            n) nodes=($OPTARG) ;;
        esac
    done
    shift $((OPTIND - 1))
    if [ "$verbose" = "1" ] ; then
        for n in "${CUBE_NODE_LIST_HOSTNAMES[@]}" ; do
            printf '%s|0|%s 999\n' "$n" "${WATCH[$n]:-active}"
        done
        return 0
    fi
    for n in "${nodes[@]}" ; do REMOTE+="$n:$1;" ; done
}

reset() {
    ETCD_UP=() ; REACH=() ; WATCH=()
    ETCD_HEALTHY=2
    CUBE_NODE_CONTROL_HOSTNAMES=($N1 $N2 $N3)
    CUBE_NODE_LIST_HOSTNAMES=($N1 $N2 $N3 $P1)
    RESTARTED="" ; REMOTE="" ; LOCAL_CUBECTL=""
    rm -f $(cntf $N1) $(cntf $N2) $(cntf $N3)
    ERR_CODE=0 ; ERR_MSG= ; ERR_LOG=
}
RESEED='cubectl this-node reset && cubectl this-node join'

# ---- third failed restart, quorum 2/3 without it: reseed, on that member -----------
reset
ETCD_UP[$N2]=0
echo 2 > "$(cntf $N2)"
health_etcd_repair 2>/dev/null
[ "$REMOTE" = "$N2:$RESEED;" ] && ok || bad "reseed not sent whole to $N2: '$REMOTE'"
[ -z "$LOCAL_CUBECTL" ] && ok || bad "cubectl ran on the repairing node: '$LOCAL_CUBECTL'"
[ "$RESTARTED" = "$N2 " ] && ok || bad "plain restart not tried first: '$RESTARTED'"
[ ! -e "$(cntf $N2)" ] && ok || bad "reseed counter not cleared after the reseed"

# ---- first failure: restart only, counter starts --------------------------------------
reset
ETCD_UP[$N2]=0
health_etcd_repair 2>/dev/null
[ -z "$REMOTE" ] && ok || bad "reseeded on the first failure: '$REMOTE'"
[ "$(cat "$(cntf $N2)" 2>/dev/null)" = "1" ] && ok || bad "counter not at 1 after one failure"

# ---- quorum lost: never reseed -----------------------------------------------------
reset
ETCD_UP[$N2]=0 ; ETCD_HEALTHY=1
echo 5 > "$(cntf $N2)"
health_etcd_repair 2>/dev/null
[ -z "$REMOTE" ] && ok || bad "reseeded without quorum: '$REMOTE'"

# ---- unreachable member: skipped, and the repair goes on ---------------------------
reset
ETCD_UP[$N1]=0 ; REACH[$N1]=0 ; echo 5 > "$(cntf $N1)"
ETCD_UP[$N3]=0
WATCH[$P1]=inactive
# In a subshell, so an Error exit out of the repair is a failed assertion here
# rather than the end of this test.
out=$( health_etcd_repair >/dev/null 2>&1 ; echo "rc=$? restarted=[$RESTARTED] remote=[$REMOTE]" )
case "$out" in *"rc=0"*) ok ;; *) bad "repair exited at the unreachable member: '$out'" ;; esac
case "$out" in *"restarted=["*"$N1"*"]"*) bad "restarted an unreachable member: $out" ;; *) ok ;; esac
case "$out" in *"restarted=["*"$N3"*"]"*) ok ;; *) bad "member after the unreachable one not restarted: $out" ;; esac
[ "$(cat "$(cntf $N1)")" = "5" ] && ok || bad "unreachable member's counter moved"
case "$out" in
    *"$P1:systemctl start etcd-watch ; cubectl tuning apply;"*) ok ;;
    *) bad "etcd-watch repair skipped after an unreachable member: $out" ;;
esac
case "$out" in *"remote=["*"$N1:"*) bad "sent a command to the unreachable member: $out" ;; *) ok ;; esac

echo "----"
echo "pass=$pass fail=$fail"
[ "$fail" -eq 0 ] && { echo "OK: health_etcd_repair reseed"; exit 0; } || exit 1
