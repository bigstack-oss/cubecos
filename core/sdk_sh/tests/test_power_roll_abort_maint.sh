#!/bin/bash
#
# Unit test for ../modules/sdk_power.sh: an abort that lands during a node's
# drain must stop the kick before the reboot and undo the node's drain-side
# state; the drain holds masakari maintenance and resume releases it (leaving
# segments the operator held). Extracts the functions and stubs OpenStack,
# mysql, ssh and remote_run. Run: bash test_power_roll_abort_maint.sh
#
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$DIR/../modules/sdk_power.sh"

for fn in _power_roll_write _power_roll_set_node_num _power_roll_aborted _power_roll_drain_live \
          _power_roll_node_settle _power_roll_kick_stop _power_roll_kick power_roll_advance \
          power_roll_decision power_node_evacuate power_node_resume _power_masakari_host_segments \
          power_node_maint_hold power_node_maint_release ; do
    body="$(awk -v f="^${fn}\\\\(\\\\)" '$0~f{p=1} p{print} p&&/^}/{exit}' "$SRC")"
    [ -n "$body" ] || { echo "FAIL: $fn not extracted"; exit 1; }
    eval "$body"
done
_power_roll_set_str() { _power_roll_write --arg v "$2" ".$1=\$v" ; }
_power_roll_set_raw() { _power_roll_write --argjson v "$2" ".$1=\$v" ; }

T=$(mktemp -d); trap 'rm -rf $T' EXIT
ROLLING_DIR=$T/rolling; mkdir -p $ROLLING_DIR
ROLLING_JOB=$ROLLING_DIR/job.json
ROLLING_RECOVER_MARKER=$T/rolling_recover
CLUSTER_ACTIVE_RUNNING=$ROLLING_DIR/active_running
CALLS=$T/calls; HOSTNAME=n1
pass=0 fail=0
chk(){ if [ "$2" = "$3" ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL: $1: got [$2] want [$3]"; fi; }
has(){ grep -qF -- "$1" $CALLS && echo y || echo n; }
job(){ jq -r "$1" $ROLLING_JOB; }

# --- stubs ---
log_info(){ :; }; log_warning(){ :; }; Quiet(){ [ "$1" = -n ] && shift; "$@" >/dev/null 2>&1; }
_power_roll_set_node_status(){ _power_roll_write --arg h "$1" --arg s "$2" '(.nodes[]|select(.hostname==$h)).status=$s'; }
_power_roll_kind(){ echo restart; }; _power_roll_cli_verb(){ echo restart; }
_power_roll_master(){ echo m1; }; _power_roll_api_ready(){ :; }; _power_roll_octavia_hm_host(){ return 1; }
_power_roll_pause(){ echo "pause $1" >> $CALLS; _power_roll_set_str state paused; }
_power_roll_watchdog_disarm(){ :; }; cluster_rolling_marker_clear(){ echo marker_clear >> $CALLS; }
is_sshable(){ return 0; }; is_control_node(){ return 1; }; ping(){ return 1; }; sleep(){ :; }
cubectl(){ echo '[{"hostname":"n1","ip":{"management":"10.0.0.1"}},{"hostname":"n2","ip":{"management":"10.0.0.2"}}]'; }
HEX_SDK=hexsdk; hexsdk(){ echo "sdk $*" >> $CALLS; return 0; }
ssh(){ echo "ssh $*" >> $CALLS; }
# remote_run: the master runs power_node_evacuate; ON_EVAC simulates what happens during the drain
ON_EVAC=:; EVAC_RC=0
remote_run(){ echo "rr $1 $2" >> $CALLS
    case "$2" in *"power_node_evacuate "*) : > $ROLLING_DIR/.drained.n1; eval "$ON_EVAC"; return $EVAC_RC ;;
                 *"virsh list"*) echo 0 ;; esac; return 0; }
# masakari hosts table as "<segment> <on_maintenance>" lines; segment host update edits it
ROWS=$T/rows; : > $ROWS
OPENSTACK=os_stub; os_stub(){ echo "os $*" >> $CALLS
    [ "$1 $2 $3" = "segment host update" ] && sed -i "s/^$4\t.*/$4\t$([ "$7" = True ] && echo 1 || echo 0)/" $ROWS; }
MYSQL=mysql_stub; mysql_stub(){ cat $ROWS; }

newjob(){ # $1 = state, $2 = n1 status
    jq -n --arg s "$1" --arg st "${2:-pending}" '{kind:"restart",state:$s,inflight:"",deadline:0,heartbeat:0,
        nodes:[{hostname:"n1",role:"control-converged",ip:"10.0.0.1",status:$st},
               {hostname:"n2",role:"control-converged",ip:"10.0.0.2",status:"pending"}]}' > $ROLLING_JOB
    : > $CALLS; rm -f $ROLLING_RECOVER_MARKER $ROLLING_DIR/.drained.* $ROLLING_DIR/.draining.*
}

# 1. abort lands during the drain -> no reboot, drain undone, job aborted, n1 pending
newjob running; ON_EVAC='_power_roll_set_str state aborted'
_power_roll_kick n1 >/dev/null
chk "1 no reboot"          "$(has 'hex_cli -c reboot')" n
chk "1 no recover marker"  "$(has 'touch')" n
chk "1 resume on master"   "$(has 'rr m1 hexsdk power_node_resume n1')" y
chk "1 not paused"         "$(has 'pause')" n
chk "1 job aborted"        "$(job .state)" aborted
chk "1 n1 pending"         "$(job '.nodes[0].status')" pending
chk "1 drained rec gone"   "$([ -e $ROLLING_DIR/.drained.n1 ] && echo y || echo n)" n

# 2. abort while the drain fails -> stop, not pause (pause would revive the job)
newjob running; ON_EVAC='_power_roll_set_str state aborted'; EVAC_RC=1
_power_roll_kick n1 >/dev/null
chk "2 no reboot"   "$(has 'hex_cli -c reboot')" n
chk "2 not paused"  "$(job .state)" aborted
EVAC_RC=0

# 3. no abort -> reboots as before
newjob running; ON_EVAC=:
_power_roll_kick n1 >/dev/null
chk "3 reboots"     "$(has 'hex_cli -c reboot')" y
chk "3 rebooting"   "$(job '.nodes[0].status')" rebooting
chk "3 no resume"   "$(has 'power_node_resume')" n

# 4. abort of a live drain leaves the undo to the kick (no race with the drain)
newjob running draining; _power_roll_set_str inflight n1; : > $ROLLING_DIR/.draining.n1; : > $CALLS
power_roll_decision abort >/dev/null
chk "4 aborted"           "$(job .state)" aborted
chk "4 inflight cleared"  "$(job .inflight)" ""
chk "4 no resume"         "$(has 'power_node_resume')" n
chk "4 no compute enable" "$(has 'compute service set')" n

# 5. abort of a dead drain (no sentinel) undoes the node itself
newjob paused draining; _power_roll_set_str inflight n1; : > $CALLS
power_roll_decision abort >/dev/null
chk "5 resume"      "$(has 'rr m1 hexsdk power_node_resume n1')" y
chk "5 n1 pending"  "$(job '.nodes[0].status')" pending

# 6. abort while rebooting -> the node's boot path settles it
newjob running rebooting; _power_roll_set_str inflight n1; : > $CALLS
power_roll_decision abort >/dev/null
chk "6 no resume"   "$(has 'power_node_resume')" n
touch $ROLLING_RECOVER_MARKER
power_roll_advance n1
chk "6 boot settles"     "$(has 'rr m1 hexsdk power_node_resume n1')" y
chk "6 n1 done"          "$(job '.nodes[0].status')" done
chk "6 marker removed"   "$([ -e $ROLLING_RECOVER_MARKER ] && echo y || echo n)" n
chk "6 still aborted"    "$(job .state)" aborted
chk "6 no next kick"     "$(job '.nodes[1].status')" pending

# 7. drain holds maintenance only where it is not already held (operator intent kept)
newjob running; printf 'segA\t0\nsegB\t1\n' > $ROWS
power_node_maint_hold n1
chk "7 holds segA"       "$(has 'os segment host update segA n1 --on_maintenance True')" y
chk "7 leaves segB"      "$(has 'segB')" n
chk "7 records segB"     "$(cat $ROLLING_DIR/.maint.n1)" segB
# 8. resume releases what the roll held, keeps the operator's, re-enables compute
: > $CALLS
power_node_resume n1
chk "8 clears segA"      "$(has 'os segment host update segA n1 --on_maintenance False')" y
chk "8 keeps segB"       "$(has 'segB')" n
chk "8 compute enable"   "$(has 'os compute service set --enable n1 nova-compute')" y
chk "8 rows"             "$(tr '\t\n' ' ;' < $ROWS)" "segA 0;segB 1;"
chk "8 record removed"   "$([ -e $ROLLING_DIR/.maint.n1 ] && echo y || echo n)" n

# 9. no masakari host -> no segment calls
: > $ROWS; : > $CALLS
power_node_maint_hold n1; power_node_maint_release n1
chk "9 no-op"            "$(has 'segment')" n

# 10. evacuate holds maintenance before the drain; a failed drain releases it
power_drain_host(){ echo drain >> $CALLS; return ${DRAIN_RC:-0}; }
_power_roll_drain_poll(){ :; }
printf 'segA\t0\n' > $ROWS; : > $CALLS; DRAIN_RC=0
power_node_evacuate n1
chk "10 hold before drain" "$(grep -n -e 'on_maintenance True' -e '^drain' $CALLS | head -1 | cut -d: -f2- | cut -c1-2)" os
chk "10 held"              "$(cut -f2 $ROWS)" 1
power_node_resume n1
DRAIN_RC=1; : > $CALLS
power_node_evacuate n1
chk "10 fail releases"     "$(has 'on_maintenance False')" y
chk "10 fail rows"         "$(cut -f2 $ROWS)" 0

echo "PASS=$pass FAIL=$fail"
[ $fail -eq 0 ]
