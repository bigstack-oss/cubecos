#!/bin/bash
#
# Unit test for re-adding pure compute nodes as Pacemaker remote nodes:
#  - pacemaker_remote_add (../modules.pre/sdk_pacemaker.sh) stops a running
#    pacemaker_remote before `pcs cluster node add-remote`, retries, and on failure
#    logs pcs's error and returns non-zero without `enable --now`.
#  - the compute branch of health_hacluster_repair (../modules/sdk_health.sh) waits
#    for quorum after restarting the control nodes and re-checks each remote node
#    with a grace period instead of trusting one early `pcs status` snapshot.
#
# Self-contained: extracts the functions, stubs pcs / remote_run / hex_sdk / sleep.
# The last section is a negative control against c2050cd6, before the fix. It is
# skipped when that git object is not available.
#
#   Run: bash test_sdk_pacemaker_remote_readd.sh   (exit 0 = pass)
#
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PM_SRC="$DIR/../modules.pre/sdk_pacemaker.sh"
HE_SRC="$DIR/../modules/sdk_health.sh"

T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
mkdir -p "$T/state"

extract() { awk -v fn="^$1\\\\(\\\\)" '$0 ~ fn {f=1} f{print} f&&/^}/{exit}' "$2"; }

load() { # load <file> <function>...: pcs runs through the stub, state files under $T
    local src=$1 fn
    shift
    for fn in "$@"; do
        eval "$(extract "$fn" "$src" | sed -e 's#timeout \$SRVSTO /usr/sbin/pcs#pcs#g' \
            -e "s#/etc/appliance/state/#$T/state/#g")"
        [ "$(type -t "$fn")" = function ] || { echo "FAIL: $fn not extracted from $src"; exit 1; }
    done
}

SRVTO=1 SRVSTO=1 HEX_SDK=true HOSTNAME=cc1 VERBOSE=0
CUBE_NODE_CONTROL_HOSTNAMES=(cc1 cc2 cc3)
CUBE_NODE_COMPUTE_HOSTNAMES=(cc1 cc2 cc3 p4 p5)
: > "$T/state/configured"

# calls are appended to $T/calls; $T/svc.<node> = pacemaker_remote running,
# $T/rsc.<node> = remote resource in the CIB, $T/online.<node> = calls to
# `pcs status` before the node shows RemoteOnline (absent = never)
call() { echo "$*" >> "$T/calls"; }
sleep() { :; }
Quiet() { [ "$1" = "-n" ] && shift; "$@" >/dev/null 2>&1; }
log_error() { echo "$*" >> "$T/errlog"; }
log_info() { :; }
cmd() { :; }
is_cluster_rolling() { return 1; }
is_sshable() { return 0; }
is_remote_running() { return 0; }
pacemaker_settled() { return 0; }
cubectl() { echo '[]'; }
jq() { :; }
is_ctrl() { case $1 in cc*) return 0 ;; esac; return 1; }
remote_run() {
    local n=$1; shift
    call "remote_run $n $*"
    case "$*" in
        *is_control_node*) is_ctrl "$n" ;;
        "systemctl stop pacemaker_remote") rm -f "$T/svc.$n" ;;
        "systemctl enable --now pacemaker_remote") : > "$T/svc.$n" ;;
        *) return 0 ;;
    esac
}
hex_sdk() {
    case $1 in
        remote_run) shift; remote_run "$@" ;;
        *) call "hex_sdk $*" ;;
    esac
}
bump() { local n=$(( $(cat "$T/$1" 2>/dev/null || echo 0) + 1 )); echo $n > "$T/$1"; echo $n; }
count() { cat "$T/$1" 2>/dev/null || echo 0; }
pcs() {
    case "$1 ${2:-}" in
        "cluster node")
            call "pcs add-remote $4"
            [ -f "$T/addfail" ] && { echo "Error: $4: pcsd down"; return 1; }
            [ -f "$T/svc.$4" ] && { echo "Error: $4: The host seems to be in a cluster already as the following service is found to be running: 'pacemaker_remote'"; return 1; }
            : > "$T/rsc.$4" ; : > "$T/svc.$4" ;;
        "resource config") [ -f "$T/rsc.$3" ] ;;
        "status "*)
            local c n on=""
            c=$(bump pcs_status)
            for n in p4 p5; do
                [ -f "$T/online.$n" ] && [ "$c" -gt "$(cat "$T/online.$n")" ] && on+=" $n"
            done
            printf '  * Online: [ cc1 cc2 cc3 ]\n  * RemoteOnline: [%s ]\n' "$on" ;;
        *) return 0 ;;
    esac
}
QUORUM_AFTER=0
crm_mon() { [ "$(bump crm)" -gt "$QUORUM_AFTER" ] && echo "Current DC: cc1 - partition with quorum"; }

pass=0 fail=0
ck() { [ "$1" = "$2" ] && pass=$((pass+1)) || { fail=$((fail+1)); echo "FAIL: $3 -> got '$1' want '$2'"; }; }
reset() { rm -f "$T"/calls "$T"/errlog "$T"/svc.* "$T"/rsc.* "$T"/online.* "$T"/addfail "$T"/pcs_status "$T"/crm; : > "$T/calls"; QUORUM_AFTER=0; }
calls() { grep -c -- "$1" "$T/calls"; }
first() { grep -n -- "$1" "$T/calls" | head -1 | cut -d: -f1; }

load "$PM_SRC" pacemaker_remote_add pacemaker_remote_exists pacemaker_remote_online
load "$HE_SRC" health_hacluster_repair _hacluster_remote_back

# ---- 1. pacemaker_remote running without a resource: stop it, then add ----
reset
: > "$T/svc.p4"
pacemaker_remote_add p4; ck "$?" 0 "running service, no resource: added"
ck "$([ -f "$T/rsc.p4" ] && echo y)" y "resource created"
ck "$([ "$(first 'stop pacemaker_remote')" -lt "$(first 'add-remote')" ] && echo y)" y "stop runs before add-remote"
ck "$(calls 'enable --now')" 1 "service enabled after the add"

# ---- 2. add-remote keeps failing: pcs's error logged, non-zero, no enable ----
reset
: > "$T/svc.p4" ; : > "$T/addfail"
out=$(pacemaker_remote_add p4 2>&1); rc=$?
ck "$rc" 1 "add-remote fails: non-zero"
ck "$(calls 'add-remote')" 3 "add-remote retried 3 times"
ck "$(calls 'enable --now')" 0 "no enable --now on failure"
ck "$(grep -c 'pacemaker_remote_add: p4 not added after 3 tries: Error: p4: pcsd down' "$T/errlog")" 1 "pcs error logged"
ck "$(echo "$out" | grep -c 'pcsd down')" 1 "pcs error on stderr"

# ---- 3. resource already there: no stop, no add-remote ----
reset
: > "$T/svc.p4" ; : > "$T/rsc.p4"
pacemaker_remote_add p4; ck "$?" 0 "existing resource: ok"
ck "$(calls 'add-remote')" 0 "existing resource: no add-remote"
ck "$(calls 'stop pacemaker_remote')" 0 "existing resource: service not stopped"

# ---- 4. control node path unchanged: one add-remote, pacemaker_remote not stopped ----
reset
pacemaker_remote_add cc2; ck "$?" 0 "control node: ok"
ck "$(calls 'add-remote')" 1 "control node: one add-remote"
ck "$(calls 'stop pacemaker_remote')" 0 "control node: pacemaker_remote not stopped"

# ---- 5. repair: wait for quorum, then re-check each node with a grace period ----
repair() { reset; QUORUM_AFTER=2; echo 2 > "$T/online.p4"; : > "$T/svc.p4"; : > "$T/svc.p5"; health_hacluster_repair >/dev/null 2>&1; }
repair
ck "$(count crm)" 3 "repair polls crm_mon until quorate"
ck "$(calls 'pacemaker_remote_remove p4')" 0 "p4 back within grace: not removed"
ck "$(calls 'pacemaker_remote_add p4')" 0 "p4 back within grace: not re-added"
ck "$(calls 'pacemaker_remote_remove p5')" 1 "p5 stays offline: removed"
ck "$(calls 'pacemaker_remote_add p5')" 1 "p5 stays offline: re-added"
ck "$(calls 'remote_run p4 systemctl stop pacemaker_remote')" 0 "p4 not bounced"

# ---- 6. negative control: before the fix ----
BASE_REF=c2050cd6
if git -C "$DIR" show "$BASE_REF:core/sdk_sh/modules.pre/sdk_pacemaker.sh" > "$T/base_pm.sh" 2>/dev/null &&
   git -C "$DIR" show "$BASE_REF:core/sdk_sh/modules/sdk_health.sh" > "$T/base_he.sh" 2>/dev/null; then
    load "$T/base_pm.sh" pacemaker_remote_add
    reset
    : > "$T/svc.p4"
    pacemaker_remote_add p4; ck "$?" 0 "negative control: unfixed add returns 0 though refused"
    ck "$([ -f "$T/rsc.p4" ] && echo y)" "" "negative control: unfixed add leaves no resource"
    ck "$(calls 'enable --now')" 1 "negative control: unfixed add enables the service anyway"
    load "$T/base_he.sh" health_hacluster_repair
    repair
    ck "$(calls 'pacemaker_remote_remove p4')" 1 "negative control: unfixed repair removes p4 from the early snapshot"
else
    echo "SKIP: negative control needs git object $BASE_REF"
fi

echo "pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
