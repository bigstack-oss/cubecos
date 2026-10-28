#!/bin/bash
#
# Unit test for the restart-roll time cuts in ../modules/sdk_power.sh and
# sdk_ceph.sh: the kick fails the mgr over before the reboot but leaves the
# dashboard check in the background; the evacuate counts VMs from one server
# list; the end-of-roll hex_config actions run only where their marker is.
# Stubs ceph, OpenStack, ssh and remote_run. Run: bash test_power_roll_time.sh
#
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$DIR/../modules/sdk_power.sh"
CSRC="$DIR/../modules/sdk_ceph.sh"
extract(){ awk -v f="^${1}\\\\(\\\\)" '$0~f{p=1} p{print} p&&/^}/{exit}' "$2"; }
for fn in _power_roll_write _power_roll_set_node_num _power_roll_aborted _power_roll_kick \
          power_roll_advance power_node_evacuate ; do
    body="$(extract $fn "$SRC")"; [ -n "$body" ] || { echo "FAIL: $fn not extracted"; exit 1; }
    eval "$body"
done
for fn in ceph_mgr_fail_off ceph_mgr_handoff ceph_mgr_dashboard_ensure ; do
    body="$(extract $fn "$CSRC")"; [ -n "$body" ] || { echo "FAIL: $fn not extracted"; exit 1; }
    eval "$body"
done
eval "$(grep -E '^ROLLING_(MYSQL_UPGRADE_DIR|TICKTIME_MARK)=' "$SRC")"
_power_roll_set_str() { _power_roll_write --arg v "$2" ".$1=\$v" ; }
_power_roll_set_raw() { _power_roll_write --argjson v "$2" ".$1=\$v" ; }

T=$(mktemp -d); trap 'rm -rf $T' EXIT
ROLLING_DIR=$T/rolling; mkdir -p $ROLLING_DIR
ROLLING_JOB=$ROLLING_DIR/job.json
ROLLING_RECOVER_MARKER=$T/rolling_recover
CALLS=$T/calls; HOSTNAME=n2
pass=0 fail=0
chk(){ if [ "$2" = "$3" ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL: $1: got [$2] want [$3]"; fi; }
has(){ grep -qF -- "$1" $CALLS && echo y || echo n; }
line(){ grep -nF -- "$1" $CALLS | head -1 | cut -d: -f1; }
job(){ jq -r "$1" $ROLLING_JOB; }

# --- stubs ---
# Quiet as in hex_sdk/functions: eval $*
log_info(){ :; }; log_warning(){ :; }; Quiet(){ [ "$1" = -n ] && shift; eval $* >/dev/null 2>&1; }
_power_roll_set_node_status(){ echo "status $1 $2" >> $CALLS; _power_roll_write --arg h "$1" --arg s "$2" '(.nodes[]|select(.hostname==$h)).status=$s'; }
_power_roll_kind(){ echo restart; }; _power_roll_cli_verb(){ echo restart; }
_power_roll_master(){ echo m1; }; _power_roll_api_ready(){ :; }; _power_roll_octavia_hm_host(){ return 1; }
_power_roll_pause(){ echo "pause $1" >> $CALLS; }
_power_roll_node_settle(){ :; }; _power_roll_watchdog_disarm(){ :; }
cluster_rolling_marker_clear(){ :; }; power_node_maint_hold(){ :; }; power_node_maint_release(){ :; }
is_sshable(){ return 0; }; is_control_node(){ return 1; }; ping(){ return 1; }; sleep(){ :; }
cubectl(){ echo '[{"hostname":"n1","ip":{"management":"10.0.0.1"}},{"hostname":"n2","ip":{"management":"10.0.0.2"}}]'; }
HEX_SDK=hexsdk; hexsdk(){ echo "sdk $*" >> $CALLS; return 0; }
HEX_CFG=hexcfg
cmd(){ echo "cmd $*" >> $CALLS; }
/usr/sbin/hex_log_event(){ :; }
ssh(){ echo "ssh $*" >> $CALLS; }
remote_run(){ echo "rr $1 $2" >> $CALLS; case "$2" in *"virsh list"*) echo 0 ;; esac; return 0; }

newjob(){ # $1 = n1 status, $2 = n2 status
    jq -n --arg a "$1" --arg b "$2" '{kind:"restart",state:"running",inflight:"",deadline:0,heartbeat:0,
        nodes:[{hostname:"n1",role:"control-converged",ip:"10.0.0.1",status:$a},
               {hostname:"n2",role:"control-converged",ip:"10.0.0.2",status:$b}]}' > $ROLLING_JOB
    : > $CALLS
}

# 1. kick: mgr failover before the reboot, dashboard check in the background
newjob pending pending
_power_roll_kick n1 >/dev/null
chk "1 mgr handoff"           "$(has 'rr m1 hexsdk ceph_mgr_handoff n1')" y
chk "1 no blocking ensure"    "$(has 'ceph_mgr_dashboard_ensure')" n
chk "1 handoff before reboot" "$([ "$(line ceph_mgr_handoff)" -lt "$(line 'hex_cli -c reboot')" ] && echo y || echo n)" y
chk "1 reboots"               "$(has 'hex_cli -c reboot')" y

# 2. a failed mgr failover is not a pause (UI-only)
remote_run(){ echo "rr $1 $2" >> $CALLS; case "$2" in *ceph_mgr_handoff*) return 1 ;; *"virsh list"*) echo 0 ;; esac; return 0; }
newjob pending pending
_power_roll_kick n1 >/dev/null
chk "2 not paused"            "$(has pause)" n
chk "2 still reboots"         "$(has 'hex_cli -c reboot')" y
remote_run(){ echo "rr $1 $2" >> $CALLS; case "$2" in *"virsh list"*) echo 0 ;; esac; return 0; }

# 3. last node lands: end-of-roll actions guarded by their markers
newjob done rebooting; _power_roll_set_str inflight n2; touch $ROLLING_RECOVER_MARKER; : > $CALLS
power_roll_advance n2 >/dev/null
chk "3 roll done"             "$(job .state)" done
mysql_cmd=$(grep -F 'upgrade_mysql' $CALLS | sed 's/^cmd -c //')
tick_cmd=$(grep -F 'rabbitmq_ticktime' $CALLS | sed 's/^cmd -c //')
chk "3 mysql guarded"         "$mysql_cmd" "[ ! -e /var/lib/_mysql ] || hexcfg upgrade_mysql"
chk "3 ticktime guarded"      "$tick_cmd" "[ ! -e /etc/appliance/state/rabbitmq_ticktime_compat ] || hexcfg rabbitmq_ticktime"
chk "3 feature flags on master" "$(has 'rr m1 hexcfg rabbitmq_feature_flags')" y
chk "3 flags before done"     "$([ "$(line rabbitmq_feature_flags)" -gt "$(line rabbitmq_ticktime)" ] && echo y || echo n)" y
# the guarded strings, run as cmd runs them remotely: hex_config only with the marker
hexcfg(){ echo "ran $*" >> $T/ran; }
run_guarded(){ : > $T/ran; eval "${1//\/var\/lib\/_mysql/$T/_mysql}" ; r=$?; eval "${2//\/etc\/appliance\/state/$T}" ; echo "$r$? $(tr '\n' ';' < $T/ran)"; }
chk "3 no markers: no hex_config, rc 0" "$(run_guarded "$mysql_cmd" "$tick_cmd")" "00 "
mkdir $T/_mysql; touch $T/rabbitmq_ticktime_compat
chk "3 markers: both run"     "$(run_guarded "$mysql_cmd" "$tick_cmd")" "00 ran upgrade_mysql;ran rabbitmq_ticktime;"

# 3b. flags the master could not enable: the roll still completes, and says so
remote_run(){ echo "rr $1 $2" >> $CALLS; case "$2" in *rabbitmq_feature_flags) return 1 ;; esac; return 0; }
log_error(){ echo "error $1" >> $CALLS; }
newjob done rebooting; _power_roll_set_str inflight n2; touch $ROLLING_RECOVER_MARKER; : > $CALLS
power_roll_advance n2 >/dev/null
chk "3b roll done"            "$(job .state)" done
chk "3b logged"               "$(has 'error rolling_restart: rabbitmq feature flags not all enabled, see the log on m1')" y
remote_run(){ echo "rr $1 $2" >> $CALLS; case "$2" in *"virsh list"*) echo 0 ;; esac; return 0; }

# 4. evacuate: one server list gives the ACTIVE total and the on-host total
newjob draining pending
OPENSTACK=os_stub
os_stub(){ echo "os $*" >> $CALLS; case "$1 $2" in "server list") printf 'a ACTIVE\nb SHUTOFF\nc ACTIVE\nd SUSPENDED\n' ;; esac; }
power_drain_host(){ echo drain >> $CALLS; return 0; }
_power_roll_drain_poll(){ echo "poll $*" >> $CALLS; }
power_node_evacuate n1
chk "4 one server list"       "$(grep -c 'os server list' $CALLS)" 1
chk "4 total ACTIVE"          "$(job '.nodes[0].vms_total')" 2
chk "4 poll gets total+all"   "$(grep '^poll' $CALLS | awk '{print $2, $3, $5}')" "n1 2 4"

# 5. ceph_mgr_fail_off: no-op off the active, waits for a new active, fails bounded
ACTIVE=m2 NEXT=m3 TICKS=0
CEPH=ceph_stub
ceph_stub(){ echo "ceph $*" >> $CALLS
    case "$*" in
        "mgr stat -f json") TICKS=$((TICKS+1)); echo "{\"active_name\":\"$ACTIVE\"}" ;;
        "mgr fail") [ -n "$NEXT" ] && ACTIVE=$NEXT ;;
    esac; }
: > $CALLS; ceph_mgr_fail_off n1; chk "5 not active: rc 0" "$?" 0
chk "5 not active: no fail"   "$(has 'mgr fail')" n
ACTIVE=n1 NEXT=m3; : > $CALLS; ceph_mgr_fail_off n1; chk "5 fails over" "$?" 0
chk "5 mgr failed"            "$(has 'ceph mgr fail')" y
ACTIVE=n1 NEXT=""; : > $CALLS; ceph_mgr_fail_off n1 2>/dev/null; chk "5 stuck: rc 1" "$?" 1
chk "5 stuck: bounded polls"  "$(grep -c 'mgr stat' $CALLS)" 31
# ceph_mgr_handoff: only an actual failover starts the background dashboard check
setsid(){ echo "setsid $*" >> $CALLS; }
ACTIVE=m2; : > $CALLS; ceph_mgr_handoff n1; chk "5 handoff off-active rc 0" "$?" 0
chk "5 handoff off-active: no bg check" "$(has setsid)" n
ACTIVE=n1 NEXT=m3; : > $CALLS; ceph_mgr_handoff n1; r=$?; wait; chk "5 handoff rc 0" "$r" 0
chk "5 handoff: bg dashboard check" "$(has 'ceph_mgr_dashboard_ensure')" y
ACTIVE=n1 NEXT=""; : > $CALLS; ceph_mgr_handoff n1 2>/dev/null; chk "5 handoff stuck rc 1" "$?" 1
chk "5 handoff stuck: no bg check" "$(has setsid)" n
unset -f setsid
# dashboard_ensure <host> keeps its old contract: no-op off the active
ACTIVE=m2; : > $CALLS; ceph_mgr_dashboard_ensure n1; chk "5 ensure off-active no-op" "$?" 0
chk "5 ensure off-active no fail" "$(has 'mgr fail')" n

echo "PASS=$pass FAIL=$fail"
[ $fail -eq 0 ]
