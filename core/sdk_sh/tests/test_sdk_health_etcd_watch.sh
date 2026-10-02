#!/bin/bash
#
# Unit test for the etcd-watch half of health_etcd_check/repair/_auto_repair in
# ../modules/sdk_health.sh (#1336) -- what "cluster check" says about a node that
# stopped applying cluster config while etcd itself stayed healthy.
#
# What is asserted: a node whose etcd-watch is not active is code 3, naming it; a node
# whose /etc/revision is older than the newest cluster.* key is code 4, naming it; a
# node whose /etc/revision only trails the store revision (terraform writes there too)
# is healthy; a node that has not finished its commit, or cannot be reached, is not
# judged; etcd's own codes 1/2 still win; repair starts the watcher and re-syncs
# exactly the affected nodes, on those nodes; auto-repair acts on code 3 only.
#
# Self-contained: extracts only the functions under test (plus _health_report and
# health_errcode_lookup) and stubs cmd, is_remote_running, etcdctl and
# _health_fail_log. The cmd stub runs the real probe string per node against a
# fixture directory, so the probe's text is under test too. No cluster, no SSH.
# Run:  bash test_sdk_health_etcd_watch.sh   (exit 0 = pass)
#
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$DIR/../modules/sdk_health.sh"

PROG=test
source "$DIR/../modules/errcodes"

for f in health_etcd_check health_etcd_repair health_etcd_report _health_etcd_watch_scan \
         _health_etcd_watch_repair _health_etcd_auto_repair _health_report \
         health_errcode_lookup ; do
    fn="$(awk -v want="^$f\\\\(\\\\)" '$0 ~ want {f=1} f{print} f&&/^}/{exit}' "$SRC")"
    [ -n "$fn" ] || { echo "FAIL: $f not found in $SRC"; exit 1; }
    eval "$fn"
done

T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT

pass=0 fail=0
ok()  { pass=$((pass+1)); }
bad() { fail=$((fail+1)); echo "FAIL: $1"; }
has()    { case "$1" in *"$2"*) ok ;; *) bad "$3: '$1'" ;; esac; }
hasnt()  { case "$1" in *"$2"*) bad "$3: '$1'" ;; *) ok ;; esac; }

# The one contract _health_report relies on: ERR_CODE comes back as the status.
_health_fail_log() { return "$ERR_CODE"; }

ERR_LOGSIZE=100
HEX_SDK=hex_sdk_marker

# ---- etcd: member/health counts and the cluster.* keys' mod_revisions ------------
ETCD_MEMBERS=3 ETCD_HEALTHY=3 CLUSTER_MODREVS="2 103 108" STORE_REV=3285
ETCDCTL=etcdctl_stub
etcdctl_stub() {
    case "$*" in
        "member list") seq "$ETCD_MEMBERS" ;;
        "endpoint health --cluster") for _ in $(seq "$ETCD_HEALTHY") ; do echo "x is healthy" ; done ;;
        "get cluster. --prefix --keys-only -w json")
            local kvs="" r
            for r in $CLUSTER_MODREVS ; do kvs+="${kvs:+,}{\"mod_revision\":$r}" ; done
            echo "{\"header\":{\"revision\":$STORE_REV},\"kvs\":[${kvs}]}" | jq -c 'if .kvs == [] then del(.kvs) else . end' ;;
        *) echo "unexpected etcdctl $*" >&2 ; return 1 ;;
    esac
}

declare -A ETCD_UP
is_remote_running() { [ "$2" = "etcd" ] && [ "${ETCD_UP[$1]:-1}" = "1" ]; }
remote_systemd_restart() { RESTARTED+="$1:$2 " ; }

# ---- per-node state: watcher, /etc/revision, commit done, reachable ---------------
declare -A WATCH REV DONE REACH
CMD_RUNS=""

# cmd [-v] [-n "<nodes>"] <command>: -v runs the probe for real against the node's
# fixture root (absolute /run and /etc paths rewritten, systemctl stubbed) and prints
# cmd's "node|ret|stdout" lines; without -v it only records what would run where.
cmd() {
    local verbose=0 nodes=() opt OPTIND=1
    while getopts "vn:" opt ; do
        case $opt in
            v) verbose=1 ;;
            n) nodes=($OPTARG) ;;
        esac
    done
    shift $((OPTIND - 1))
    [ ${#nodes[@]} -gt 0 ] || nodes=("${CUBE_NODE_LIST_HOSTNAMES[@]}")
    local n root probe out ret
    for n in "${nodes[@]}" ; do
        if [ "$verbose" = "0" ] ; then
            CMD_RUNS+="$n:$1;"
            continue
        fi
        if [ "${REACH[$n]:-1}" != "1" ] ; then
            printf '%s|%s|%s\n' "$n" 255 ""
            continue
        fi
        root=$T/$n ; rm -rf "$root" ; mkdir -p "$root/run" "$root/etc"
        [ "${DONE[$n]:-1}" = "1" ] && touch "$root/run/cube_commit_done"
        [ -n "${REV[$n]:-}" ] && printf '%s' "${REV[$n]}" > "$root/etc/revision"
        probe=${1//\/run\//$root/run/}
        probe=${probe//\/etc\//$root/etc/}
        out=$(STATE=${WATCH[$n]:-active} bash -c "systemctl() { echo \$STATE ; } ; $probe" 2>&1)
        ret=$?
        printf '%s|%s|%s\n' "$n" "$ret" "$out"
    done
}

reset() {
    WATCH=() ; REV=() ; DONE=() ; REACH=() ; ETCD_UP=()
    ETCD_MEMBERS=3 ETCD_HEALTHY=3 CLUSTER_MODREVS="2 103 108" STORE_REV=3285
    CUBE_NODE_CONTROL_HOSTNAMES=(c1 c2 c3)
    CUBE_NODE_LIST_HOSTNAMES=(c1 c2 c3 p1)
    # The live cube4510 shape: every /etc/revision trails the store revision 3285,
    # because terraform's writes moved it after each node's boot-time pull.
    REV[c1]=2861 ; REV[c2]=3005 ; REV[c3]=3145 ; REV[p1]=3001
    CMD_RUNS="" ; RESTARTED=""
    ERR_CODE=0 ; ERR_MSG= ; ERR_LOG= ; DESCRIPTION= ; FORMAT=
}

# ---- healthy, every /etc/revision behind the store but past every cluster.* key ---
reset
health_etcd_check ; rc=$?
[ "$rc" -eq 0 ] && ok || bad "healthy cluster returned $rc, want 0 (msg: $ERR_MSG)"

# ---- exactly at the newest cluster.* key: still healthy (not "<=") ----------------
reset
REV[c3]=108
health_etcd_check ; rc=$?
[ "$rc" -eq 0 ] && ok || bad "revision equal to the newest key returned $rc, want 0"

# ---- watcher stopped on c3 (the #1336 shape): code 3, naming c3 only --------------
reset
WATCH[c3]=inactive
health_etcd_check ; rc=$?
[ "$rc" -eq 3 ] && ok || bad "stopped watcher returned $rc, want 3"
has   "$ERR_MSG" "c3 etcd-watch is inactive" "message does not name the stopped node"
hasnt "$ERR_MSG" "c1 " "message named a healthy node"
has   "$ERR_LOG" "-u etcd-watch" "ERR_LOG does not point at the watcher's journal"

# ---- a crash-looping watcher is down too ------------------------------------------
reset
WATCH[p1]=activating
health_etcd_check ; rc=$?
[ "$rc" -eq 3 ] && ok || bad "activating watcher returned $rc, want 3"
has "$ERR_MSG" "p1 etcd-watch is activating" "compute node's watcher not named"

# ---- watcher running, node missed a change: code 4, naming it ---------------------
reset
CLUSTER_MODREVS="2 103 108 3286"
REV[c1]=3286 ; REV[c2]=3286 ; REV[p1]=3286 ; REV[c3]=3145
health_etcd_check ; rc=$?
[ "$rc" -eq 4 ] && ok || bad "stale node returned $rc, want 4"
has   "$ERR_MSG" "c3 cluster config at revision 3145, etcd at 3286" "message does not name the stale node"
hasnt "$ERR_MSG" "c2 " "message named an up-to-date node"

# ---- both: the dead watcher (the cause) outranks staleness (the symptom) ----------
reset
CLUSTER_MODREVS="2 103 108 3286"
REV[c1]=3286 ; REV[c2]=3000 ; REV[p1]=3286 ; REV[c3]=3145
WATCH[c3]=inactive
health_etcd_check ; rc=$?
[ "$rc" -eq 3 ] && ok || bad "down+stale returned $rc, want 3"
has "$ERR_MSG" "c2 cluster config at revision 3000" "stale node missing beside the down one"
has "$ERR_MSG" "c3 etcd-watch is inactive" "down node missing beside the stale one"

# ---- no /etc/revision at all (never pulled): behind any cluster.* key -------------
reset
unset 'REV[p1]'
health_etcd_check ; rc=$?
[ "$rc" -eq 4 ] && ok || bad "missing /etc/revision returned $rc, want 4"
has "$ERR_MSG" "p1 cluster config at revision 0" "node with no /etc/revision not named"

# ---- commit not done yet (a boot in progress): not judged -------------------------
reset
WATCH[p1]=inactive ; DONE[p1]=0 ; unset 'REV[p1]'
health_etcd_check ; rc=$?
[ "$rc" -eq 0 ] && ok || bad "node still booting returned $rc, want 0 (msg: $ERR_MSG)"

# ---- unreachable node: left to link/bootstrap ---------------------------------------
reset
WATCH[p1]=inactive ; REACH[p1]=0
health_etcd_check ; rc=$?
[ "$rc" -eq 0 ] && ok || bad "unreachable node returned $rc, want 0"

# ---- no cluster.* keys: nothing to be behind ----------------------------------------
reset
CLUSTER_MODREVS=""
REV[c1]=0
health_etcd_check ; rc=$?
[ "$rc" -eq 0 ] && ok || bad "empty cluster prefix returned $rc, want 0"

# ---- etcd's own faults still win ----------------------------------------------------
reset
ETCD_UP[c2]=0 ; WATCH[c3]=inactive
health_etcd_check ; rc=$?
[ "$rc" -eq 1 ] && ok || bad "etcd down + watcher down returned $rc, want 1"
reset
ETCD_HEALTHY=2 ; WATCH[c3]=inactive
health_etcd_check ; rc=$?
[ "$rc" -eq 2 ] && ok || bad "etcd offline + watcher down returned $rc, want 2"

# ---- report round-trips the new codes through health_errcode_lookup ---------------
for code in 3 4 ; do
    reset
    if [ $code -eq 3 ] ; then WATCH[c3]=inactive ; else CLUSTER_MODREVS="3286" ; fi
    FORMAT=line
    out="$(health_etcd_report)"
    want="$(health_errcode_lookup etcd $code)"
    case "$want" in *undefined*) bad "etcd code $code has no description in errcodes" ;; *) ok ;; esac
    has "$out" "error_code=$code,description=$want" "report did not round-trip code $code"
done

# ---- repair: start + re-sync exactly the affected nodes, through cmd -n -----------
reset
CLUSTER_MODREVS="2 103 108 3286"
REV[c1]=3286 ; REV[c2]=3286 ; REV[p1]=3000 ; REV[c3]=3145
WATCH[c3]=inactive
health_etcd_repair
want_cmd='systemctl start etcd-watch ; cubectl tuning apply'
[ "$CMD_RUNS" = "c3:$want_cmd;p1:$want_cmd;" ] && ok \
    || bad "repair did not start+re-sync exactly c3 and p1: '$CMD_RUNS'"
[ -z "$RESTARTED" ] && ok || bad "repair restarted a healthy etcd: '$RESTARTED'"

# ---- repair on a healthy cluster calls nothing --------------------------------------
reset
health_etcd_repair
[ -z "$CMD_RUNS" ] && ok || bad "repair on a healthy cluster ran: '$CMD_RUNS'"

# ---- auto-repair on code 3: only the down node, not a merely-behind one -----------
reset
CLUSTER_MODREVS="2 103 108 3286"
REV[c1]=3286 ; REV[c2]=3286 ; REV[p1]=3000 ; REV[c3]=3145
WATCH[c3]=inactive
ERR_CODE=3
_health_etcd_auto_repair
[ "$CMD_RUNS" = "c3:$want_cmd;" ] && ok || bad "auto-repair on code 3 touched: '$CMD_RUNS'"

# ---- auto-repair on codes 1, 2 and 4: calls nothing ----------------------------------
for code in 1 2 4 ; do
    reset
    CLUSTER_MODREVS="3286"
    ERR_CODE=$code
    _health_etcd_auto_repair
    [ -z "$CMD_RUNS" ] && ok || bad "auto-repair on code $code ran: '$CMD_RUNS'"
done

# ---- auto-repair dispatch is by name: _health_fail_log looks up
# "_health_<srv>_auto_repair" by that exact string, so a typo means no auto-repair.
declare -F _health_etcd_auto_repair >/dev/null 2>&1 && ok \
    || bad "_health_etcd_auto_repair is not defined by that exact name"

echo "----"
echo "pass=$pass fail=$fail"
[ "$fail" -eq 0 ] && { echo "OK: health_etcd_check/report/repair etcd-watch"; exit 0; } || exit 1
