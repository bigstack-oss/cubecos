#!/bin/bash
#
# Unit test for _health_neutron_auto_repair in ../modules/sdk_health.sh, ERR_CODE 1.
#
# health_vip_check calls this branch with no readiness gate, so on a cluster power cycle
# it runs while the computes are still waiting for the controls to bootstrap. Restarting
# neutron-ovn-metadata-agent there pulls up openvswitch (Requires=), which takes eth0
# into the provider bridge while the management address is still on eth0, and the
# compute drops off the network for good. Observed on QA 10.32.36.10: both computes cut
# off from 14:42:56, the power cycle stuck until a manual re-plumb at 16:22.
#
# So the compute agents are restarted only where cube_node_ready passes; neutron-server
# on the controls is restarted as before.
#
# Self-contained: extracts only the function under test and stubs cmd, systemctl,
# hex_sdk, openstack and ceph, so it needs no cluster.
#   Run: bash test_neutron_auto_repair_bringup_guard.sh   (exit 0 = pass)
#
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$DIR/../modules/sdk_health.sh"

body="$(awk '/^_health_neutron_auto_repair\(\)/{p=1} p{print} p&&/^}/{exit}' "$SRC")"
[ -n "$body" ] || { echo "FAIL: _health_neutron_auto_repair not extracted"; exit 1; }
eval "$body"

pass=0 fail=0
chk() { if [ "$2" = "$3" ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL: $1: got [$2] want [$3]"; fi; }

# ---- fixture ---------------------------------------------------------------
# READY[node]=0|1 is what cube_node_ready answers on that node. Restarts are logged as
# "<node>:<unit>", sorted, so the assertions do not depend on node order.
declare -A READY
LOG=$(mktemp)
CONTROLS="c1 c2 c3" COMPUTES="p4 p5"

hexsdk_stub() { [ "$1" = cube_node_ready ] && [ "${READY[$NODE]:-0}" = 1 ] ; }
systemctl() { [ "$1" = restart ] && echo "$NODE:$2" >> "$LOG" ; return 0 ; }
cmd() {     # cmd -c|-p <command...>, run "on" each node with NODE set
    local nodes
    case $1 in -c) nodes=$CONTROLS ;; -p) nodes=$COMPUTES ;; *) return 1 ;; esac
    shift
    local n
    for n in $nodes ; do ( NODE=$n ; eval "$*" ) ; done
    return 0
}
OPENSTACK=true CEPH=true HEX_SDK=hexsdk_stub

restarts() { sort "$LOG" | tr '\n' ' ' ; }
run() { : > "$LOG" ; ERR_CODE=1 _health_neutron_auto_repair ; }

# 1. power cycle: controls up, computes still waiting to bootstrap -> computes untouched
READY=([c1]=1 [c2]=0 [c3]=0 [p4]=0 [p5]=0)
run
chk "1 bring-up" "$(restarts)" "c1:neutron-server c2:neutron-server c3:neutron-server "

# 2. one compute done, one still bringing itself up -> only the ready one
READY=([c1]=1 [c2]=1 [c3]=1 [p4]=0 [p5]=1)
run
chk "2 mixed" "$(restarts)" "c1:neutron-server c2:neutron-server c3:neutron-server p5:neutron-ovn-metadata-agent p5:neutron-ovn-vpn-agent "

# 3. instance-HA on a running cluster: every compute is up -> all agents restarted
READY=([c1]=1 [c2]=1 [c3]=1 [p4]=1 [p5]=1)
run
chk "3 running" "$(restarts)" "c1:neutron-server c2:neutron-server c3:neutron-server p4:neutron-ovn-metadata-agent p4:neutron-ovn-vpn-agent p5:neutron-ovn-metadata-agent p5:neutron-ovn-vpn-agent "

rm -f "$LOG"
echo "----" ; echo "PASS=$pass FAIL=$fail"
[ "$fail" -eq 0 ] && { echo "OK: neutron auto repair bring-up guard" ; exit 0 ; } || exit 1
