#!/bin/bash
#
# Unit test for roll event tags: the live_migration_gate event
# (../../main/proj_functions) tags the gating node when there is no drain host
# and carries the active roll's sub; an abort during a drain logs
# result=aborted with the skipped count, and power_node_evacuate records only
# the VMs actually handled. Extracts the functions and stubs OpenStack, nova,
# mysql and the probes. Run: bash test_power_roll_event_tags.sh
#
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$DIR/../modules/sdk_power.sh"
PF="$DIR/../../main/proj_functions"
extract(){ awk -v f="^${2}\\\\(\\\\)" '$0~f{p=1} p{print} p&&/^}/{exit}' "$1"; }
for fn in live_migration_gate:$PF power_drain_host:$SRC power_node_evacuate:$SRC _power_roll_write:$SRC ; do
    body="$(extract "${fn#*:}" "${fn%%:*}")"
    [ -n "$body" ] || { echo "FAIL: ${fn%%:*} not extracted"; exit 1; }
    eval "$body"
done
eval "$(grep '^_power_roll_set_node_num()' "$SRC")"

T=$(mktemp -d); trap 'rm -rf $T' EXIT
ROLLING_DIR=$T/rolling; mkdir -p $ROLLING_DIR
ROLLING_JOB=$ROLLING_DIR/job.json
CLUSTER_ACTIVE_RUNNING=$ROLLING_DIR/active_running
CALLS=$T/calls; : > $CALLS; HOSTNAME=n1
pass=0 fail=0
chk(){ if [ "$2" = "$3" ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL: $1: got [$2] want [$3]"; fi; }
ev(){ grep "event -e $1" $CALLS | tail -1; }

# --- stubs ---
log_info(){ :; }; log_warning(){ :; }; log_error(){ :; }; Quiet(){ [ "$1" = -n ] && shift; "$@" >/dev/null 2>&1; }
/usr/sbin/hex_log_event(){ echo "event $*" >> $CALLS; }
sleep(){ :; }; is_control_node(){ return 0; }; remote_run(){ return 0; }; influx_event(){ :; }
HEX_SDK=hexsdk; hexsdk(){ :; }; CEPH=ceph; OPENSTACK=openstack; HEX_CLI=hexcli; SRVLTO=1
newjob(){ jq -n --arg s "$1" --arg k "$2" '{kind:$k,state:$s,nodes:[{hostname:"n1"},{hostname:"n2"}]}' > $ROLLING_JOB; }

# --- gate: probes pass on the second round (first fails galera -> repaired) ---
_live_migration_repair(){ :; }
_lmg_probe(){ local d=$1 p n ; shift
    for p in "$@" ; do n=${p%% *} ; echo 0 > "$d/$n.rc"
        case $n in
            mysql) [ -e $T/galera_ok ] || { echo 1 > "$d/$n.rc" ; touch $T/galera_ok ; } ;;
            unsync) echo 0 > "$d/$n" ;;
            health) echo HEALTH_OK > "$d/$n" ;;
            status) echo '{"osdmap":{"num_in_osds":3,"num_up_osds":3}}' > "$d/$n" ;;
            compute) printf 'nova-conductor n1 up\nnova-scheduler n1 up\nnova-compute n1 up\nnova-compute n2 up\n' > "$d/$n" ;;
            cinder) echo up > "$d/$n" ;;
            neutron) echo True > "$d/$n" ;;
        esac
    done; }
gate(){ rm -f $T/galera_ok; live_migration_gate 30 "$@" >/dev/null; }

newjob running restart
gate "" repair
chk "boot gate host" "$(ev CLU00011I | grep -o 'host=[^,]*')" "host=n1"
chk "boot gate sub" "$(ev CLU00011I | grep -o 'sub=[^,]*')" "sub=rolling_restart"
gate n2 repair
chk "drain gate host" "$(ev CLU00011I | grep -o 'host=[^,]*')" "host=n2"
newjob paused upgrade
gate "" repair
chk "upgrade gate sub" "$(ev CLU00011I | grep -o 'sub=[^,]*')" "sub=rolling_upgrade"
newjob done restart
gate "" repair
chk "no roll -> no sub" "$(ev CLU00011I | grep -c 'sub=')" "0"
chk "gate event shape" "$(ev CLU00011I | grep -c 'host=n1,category=cluster,action=gate_passed')" "1"

# --- drain: 4 VMs, maxconc 3; the abort lands after the first 3 start ---
VMS="v1 v2 v3 v4"
OPENSTACK=os_stub
os_stub(){ case "$*" in
    "server list --host n1 --all-projects --status ACTIVE -f value -c ID") printf '%s\n' $VMS ;;
    "server list --host n1 --all-projects -f value -c ID -c Status") for v in $VMS ; do echo "$v ACTIVE" ; done ;;
    esac; }
cubectl(){ echo '[{"hostname":"n1"},{"hostname":"n2"}]'; }
_power_nonmigratable_vms(){ :; }; _power_roll_kind(){ echo restart; }
nova(){ return 0; }
MYSQL=mysql_stub; mysql_stub(){ case "$*" in *"SELECT host"*) echo n2 ;; esac; }
ABORT_AFTER=1
_power_roll_aborted(){ local n=$(cat $T/ab 2>/dev/null || echo 0); echo $((n+1)) > $T/ab; [ $n -ge $ABORT_AFTER ]; }

newjob running restart
rm -f $T/ab; _POWER_DRAIN_SKIPPED=0
power_drain_host n1 >/dev/null 2>&1
chk "aborted drain rc" "$?" "0"
chk "aborted drain result" "$(ev CLU00008I | grep -o 'result=[^,]*')" "result=aborted"
chk "aborted drain migrated" "$(ev CLU00008I | grep -o 'migrated=[^,]*')" "migrated=3"
chk "aborted drain skipped" "$(ev CLU00008I | grep -o 'skipped=[^,]*')" "skipped=1"

ABORT_AFTER=99; rm -f $T/ab
power_drain_host n1 >/dev/null 2>&1
chk "full drain result" "$(ev CLU00008I | grep -o 'result=[^,]*')" "result=ok"
chk "full drain migrated" "$(ev CLU00008I | grep -o 'migrated=[^,]*')" "migrated=4"
chk "full drain no skipped" "$(ev CLU00008I | grep -c 'skipped=')" "0"

# --- evacuate: vms_done counts only what the drain handled ---
power_node_maint_hold(){ :; }; power_node_maint_release(){ :; }; _power_roll_drain_poll(){ :; }
power_drain_host(){ _POWER_DRAIN_SKIPPED=$SKIP; return 0; }
SKIP=1; power_node_evacuate n1 >/dev/null 2>&1
chk "aborted vms_done" "$(jq -r '.nodes[0].vms_done' $ROLLING_JOB)/$(jq -r '.nodes[0].vms_total' $ROLLING_JOB)" "3/4"
SKIP=0; power_node_evacuate n1 >/dev/null 2>&1
chk "full vms_done" "$(jq -r '.nodes[0].vms_done' $ROLLING_JOB)/$(jq -r '.nodes[0].vms_total' $ROLLING_JOB)" "4/4"

echo "pass=$pass fail=$fail"
[ $fail -eq 0 ]
