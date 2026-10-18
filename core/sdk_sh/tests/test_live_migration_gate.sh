#!/bin/bash
#
# Unit test for live_migration_gate in ../../main/proj_functions: probes run in
# parallel per tier, one compute service list serves every nova check, and the
# blocking cause is still named in the old order (foundation first, the
# OpenStack tier only once the foundation is healthy). Stubs hex_sdk, ceph,
# openstack and remote_run. Run: bash test_live_migration_gate.sh
#
D="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
T=$(mktemp -d); trap 'rm -rf $T' EXIT
for f in _lmg_probe live_migration_gate ; do
    sed -n "/^$f()/,/^}/p" $D/../../main/proj_functions
done > $T/fn.sh
source $T/fn.sh
pass=0 fail=0
chk(){ if [ "$2" = "$3" ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL: $1: got [$2] want [$3]"; fi; }

CALLS=$T/calls
is_control_node(){ return 0; }
log_info(){ :; }; log_warning(){ :; }; log_error(){ :; }; Quiet(){ :; }
_live_migration_repair(){ echo "repair $1" >> $CALLS; }
sleep(){ :; }
# fixture state
MYSQL_RC=0 RMQ_RC=0 UNSYNC=0 CEPH_HEALTH=HEALTH_OK CEPH_CHECKS={} INDOWN=0 DELAY=0
SERVICES="nova-conductor c1 up
nova-scheduler c1 up
nova-compute c1 up
nova-compute c2 up
nova-compute c3 up"
CINDER=up NEUTRON=True MOUNTED="c1 c2 c3"
HEX_SDK=sdk
sdk(){ echo "sdk $*" >> $CALLS; command sleep $DELAY
    case "$*" in
        *health_mysql_check) return $MYSQL_RC ;;
        *health_rabbitmq_check) return $RMQ_RC ;;
        rabbitmq_unsynced_mirror_count) echo $UNSYNC ;;
    esac; }
CEPH=ceph_stub
ceph_stub(){ echo "ceph $*" >> $CALLS; command sleep $DELAY
    case "$1" in
        health) echo $CEPH_HEALTH ;;
        status) echo "{\"health\":{\"checks\":$CEPH_CHECKS},\"osdmap\":{\"num_in_osds\":9,\"num_up_osds\":$((9 - INDOWN))}}" ;;
    esac; }
OPENSTACK=os_stub
os_stub(){ echo "os $*" >> $CALLS; command sleep $DELAY
    case "$1 $2" in
        "compute service") printf '%s\n' "$SERVICES" ;;
        "volume service") echo $CINDER ;;
        "network agent") echo $NEUTRON ;;
    esac; }
remote_run(){ echo "rr $1" >> $CALLS; case " $MOUNTED " in *" $1 "*) return 0 ;; esac; return 1; }
gate(){ : > $CALLS; live_migration_gate "${1:-1}" "${2:-}" "${3:-}" 2>/dev/null && echo pass || echo blocked; }
n(){ grep -c -- "$1" $CALLS; }

# 1. healthy: passes, one compute service list for all nova checks
chk "1 healthy passes"           "$(gate 5 c1)" pass
chk "1 one compute service list" "$(n 'os compute service list')" 1
chk "1 no per-binary list"       "$(n 'service nova')" 0
chk "1 targets skip drain host"  "$(n 'rr c1')" 0
chk "1 other targets probed"     "$(n 'rr c')" 2

# 2. foundation down: named first, the OpenStack tier is not probed
MYSQL_RC=1 CINDER=down
chk "2 galera blocks"            "$(gate 1 c1 2>&1)" blocked
chk "2 no openstack probe"       "$(n '^os ')" 0
MYSQL_RC=0; RMQ_RC=1
gate 1 c1 repair >/dev/null
chk "2 rabbitmq named (repair)"  "$(grep -m1 repair $CALLS)" "repair rabbitmq"
RMQ_RC=0 UNSYNC=2;  gate 1 c1 repair >/dev/null; chk "2 rabbitmq-sync named" "$(grep -m1 repair $CALLS)" "repair rabbitmq-sync"
UNSYNC=0 CEPH_HEALTH="HEALTH_WARN 3 pgs peering"; chk "2 ceph peering blocks" "$(gate 1 c1)" blocked
CEPH_HEALTH=HEALTH_OK INDOWN=2;                    chk "2 osd in-but-down blocks" "$(gate 1 c1)" blocked
INDOWN=0
chk "2 cinder still checked last" "$(gate 1 c1 repair >/dev/null; grep -m1 repair $CALLS)" "repair cinder-volume"
CINDER=up
# 19.2.7 on a cluster upgraded from reef: an error the roll cannot clear until it is done
CEPH_HEALTH="HEALTH_ERR 2 auth client entities with insecure key types"
CEPH_CHECKS='{"AUTH_INSECURE_SERVICE_TICKETS":{"severity":"HEALTH_ERR"},"AUTH_INSECURE_CLIENT_KEY_TYPE":{"severity":"HEALTH_WARN"}}'
chk "2 insecure cephx error passes" "$(gate 1 c1)" pass
CEPH_CHECKS='{"AUTH_INSECURE_SERVICE_TICKETS":{"severity":"HEALTH_ERR"},"OSD_FULL":{"severity":"HEALTH_ERR"}}'
chk "2 other ceph error blocks"     "$(gate 1 c1)" blocked
gate 1 c1 repair >/dev/null;  chk "2 ceph error named" "$(grep -m1 repair $CALLS)" "repair ceph"
CEPH_HEALTH=HEALTH_OK CEPH_CHECKS={}

# 3. nova checks read the single list, in the old order
SERVICES_OK=$SERVICES
SERVICES=$(printf '%s\n' "$SERVICES_OK" | sed 's/^nova-conductor c1 up/nova-conductor c1 down/')
gate 1 c1 repair >/dev/null; chk "3 conductor down"        "$(grep -m1 repair $CALLS)" "repair nova-conductor"
SERVICES=$(printf '%s\n' "$SERVICES_OK" | sed 's/^nova-scheduler c1 up/nova-scheduler c1 down/')
gate 1 c1 repair >/dev/null; chk "3 scheduler down"        "$(grep -m1 repair $CALLS)" "repair nova-scheduler"
SERVICES=$(printf '%s\n' "$SERVICES_OK" | sed 's/^nova-compute c1 up/nova-compute c1 down/')
gate 1 c1 repair >/dev/null; chk "3 drain host down named" "$(grep -m1 repair $CALLS)" "repair drain-host-nova-down"
chk "3 drain host down blocks"   "$(gate 1 c1)" blocked
chk "3 no drain host: passes"    "$(gate 1)" pass
SERVICES=$SERVICES_OK
MOUNTED="c1"
gate 1 c1 repair >/dev/null; chk "3 no storage-ready target" "$(grep -m1 repair $CALLS)" "repair no-storage-ready-target"
MOUNTED="c3"; chk "3 one target enough"  "$(gate 1 c1)" pass
SERVICES=$(printf '%s\n' "$SERVICES_OK" | sed 's/^nova-compute c3 up/nova-compute c3 down/')
gate 1 c1 repair >/dev/null; chk "3 down compute is no target" "$(grep -m1 repair $CALLS)" "repair no-storage-ready-target"
SERVICES=$SERVICES_OK MOUNTED="c1 c2 c3"
NEUTRON=False; gate 1 c1 repair >/dev/null; chk "3 neutron" "$(grep -m1 repair $CALLS)" "repair neutron"
NEUTRON=True
SERVICES=""; gate 1 c1 repair >/dev/null; chk "3 api down -> conductor" "$(grep -m1 repair $CALLS)" "repair nova-conductor"
SERVICES=$SERVICES_OK

# 4. probes run in parallel: 8 one-second probes take ~2 tiers, not 8 s
DELAY=1; s=$(date +%s); r=$(gate 30 c1); e=$(( $(date +%s) - s ))
chk "4 parallel pass"            "$r" pass
chk "4 wall clock <= 4s"         "$([ $e -le 4 ] && echo y || echo "n ($e s)")" y
DELAY=0

# 5. the probe dir is removed on both exits
ls -d /tmp/lmg.* 2>/dev/null > $T/before
gate 1 c1 >/dev/null; MYSQL_RC=1; gate 1 c1 >/dev/null; MYSQL_RC=0
ls -d /tmp/lmg.* 2>/dev/null > $T/after
chk "5 no probe dir left"        "$(comm -13 $T/before $T/after)" ""

echo "PASS=$pass FAIL=$fail"
[ $fail -eq 0 ]
