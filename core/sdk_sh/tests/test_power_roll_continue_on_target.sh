#!/bin/bash
#
# Unit test for power_roll_decision continue (../modules/sdk_power.sh) when the in-flight node
# already runs the target firmware, #2164: its boot found the job paused, so continue lands it
# as power_roll_advance would have -- settles it, reconciles its drained VMs, drops its drain
# record and removes the kick marker on the node -- and marks it done. A node not on target is
# reset to pending and left to the re-kick. Extracts the functions and stubs ssh, remote_run
# and the roll driver. Run: bash test_power_roll_continue_on_target.sh
#
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$DIR/../modules/sdk_power.sh"
for fn in _power_roll_write _power_roll_set_node_num _power_roll_node_settle power_roll_decision ; do
    body="$(awk -v f="^${fn}\\\\(\\\\)" '$0~f{p=1} p{print} p&&/^}/{exit}' "$SRC")"
    [ -n "$body" ] || { echo "FAIL: $fn not extracted"; exit 1; }
    eval "$body"
done
_power_roll_set_str() { _power_roll_write --arg v "$2" ".$1=\$v" ; }
_power_roll_set_raw() { _power_roll_write --argjson v "$2" ".$1=\$v" ; }

T=$(mktemp -d); trap 'rm -rf $T' EXIT
ROLLING_DIR=$T/rolling; mkdir -p $ROLLING_DIR
ROLLING_JOB=$ROLLING_DIR/job.json
ROLLING_RECOVER_MARKER=/store/rolling_recover
CLUSTER_ACTIVE_RUNNING=$ROLLING_DIR/active_running
CALLS=$T/calls
pass=0 fail=0
chk(){ if [ "$2" = "$3" ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL: $1: got [$2] want [$3]"; fi; }
has(){ grep -qF -- "$1" $CALLS && echo y || echo n; }
job(){ jq -r "$1" $ROLLING_JOB; }

# --- stubs ---
log_info(){ :; }; Quiet(){ [ "$1" = -n ] && shift; "$@" >/dev/null 2>&1; }
_power_roll_set_node_status(){ _power_roll_write --arg h "$1" --arg s "$2" '(.nodes[]|select(.hostname==$h)).status=$s'; }
_power_roll_kind(){ echo upgrade; }; _power_roll_master(){ echo m1; }
_power_roll_watchdog_disarm(){ :; }; _power_roll_watchdog_arm(){ :; }
power_roll_advance(){ echo advance >> $CALLS; }
HEX_SDK=hexsdk; hexsdk(){ echo "sdk $*" >> $CALLS; }
remote_run(){ echo "rr $1 $2" >> $CALLS; }
timeout(){ shift; "$@"; }
ssh(){ echo "ssh $*" >> $CALLS; }
ON_TARGET=0; _power_roll_node_on_target(){ return $ON_TARGET; }

newjob(){ # paused upgrade roll with n1 in flight
    jq -n '{kind:"upgrade",version:"/var/update/CUBE_3.2.0_x_98507040.pkg",state:"paused",inflight:"n1",
        deadline:1,reason:"watchdog",heartbeat:0,
        nodes:[{hostname:"n1",role:"control-converged",ip:"10.0.0.1",status:"finalizing",started:5,finished:0},
               {hostname:"n2",role:"control-converged",ip:"10.0.0.2",status:"pending",started:0,finished:0}]}' > $ROLLING_JOB
    : > $CALLS; : > $ROLLING_DIR/.drained.n1
}

# 1. in-flight node already on target: landed, then the roll resumes
newjob; ON_TARGET=0
power_roll_decision continue >/dev/null
chk "1 n1 done"             "$(job '.nodes[0].status')" done
chk "1 finished stamped"    "$([ "$(job '.nodes[0].finished')" -gt 0 ] && echo y || echo n)" y
chk "1 settled on master"   "$(has 'rr m1 hexsdk power_node_resume n1')" y
chk "1 VMs reconciled"      "$(has 'sdk power_vm_reconcile_error_state n1')" y
chk "1 drain record gone"   "$([ -e $ROLLING_DIR/.drained.n1 ] && echo y || echo n)" n
chk "1 kick marker removed" "$(has 'ssh -o ConnectTimeout=5 root@10.0.0.1 rm -f /store/rolling_recover')" y
chk "1 inflight cleared"    "$(job .inflight)" ""
chk "1 running again"       "$(job .state)" running
chk "1 advanced"            "$(has advance)" y

# 2. not on target: back to pending for the re-kick, nothing landed
newjob; ON_TARGET=1
power_roll_decision continue >/dev/null
chk "2 n1 pending"          "$(job '.nodes[0].status')" pending
chk "2 no settle"           "$(has 'power_node_resume')" n
chk "2 marker kept"         "$(has 'rolling_recover')" n
chk "2 advanced"            "$(has advance)" y

echo "pass=$pass fail=$fail"; [ $fail -eq 0 ]
