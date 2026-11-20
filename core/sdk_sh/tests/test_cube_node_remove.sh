#!/bin/bash
#
# Unit test for cube_node_remove (../../main/proj_functions), cluster > remove_node.
#   - a node with the control role is never removed: control, control-converged, edge-core and
#     moderator, by role bit as `cubectl node list -r control` matches them, so control-converged
#     is refused although it also has the compute and storage bits; roles that cannot be read
#     refuse too
#   - nothing changes unless the node is shut down, carries no instance and ceph can do without
#     it; each refusal says why
#   - every step runs and reports, a failed step does not stop the others, and the node leaves
#     `cubectl node list` only when every step succeeded; a failure returns non-zero
#   - a node without the compute role (storage, network) gets the ceph and pacemaker steps only
#   - cube_data_node_list, the nodes the CLI offers, is every node without the control role
#   - the node is matched by its whole hostname: cn1 is not cn10
#
# Self-contained: extracts the functions and records the calls they make instead of running
# them, so it needs no node.
#   Run: bash test_cube_node_remove.sh   (exit 0 = pass)
#   PROJ_FUNCTIONS=<file> runs it against another copy of proj_functions.
#
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="${PROJ_FUNCTIONS:-$DIR/../../main/proj_functions}"
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT

for f in _cube_node_remove_step _cube_node_remove_pacemaker _cube_node_role_test cube_node_remove cube_data_node_list ; do
    body="$(awk "/^$f\(\)/{p=1} p{print} p&&/^}/{exit}" "$SRC")"
    [ -n "$body" ] || { echo "FAIL: $f not extracted"; exit 1; }
    eval "$body"
done

pass=0 fail=0
chk() { if [ "$2" = "$3" ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL: $1: got [$2] want [$3]"; fi; }

NODES='[{"hostname":"cc1","role":"control-converged"},{"hostname":"e1","role":"edge-core"},{"hostname":"m1","role":"moderator"},
        {"hostname":"cn1","role":"compute"},{"hostname":"cn10","role":"compute"},{"hostname":"s1","role":"storage"},{"hostname":"n1","role":"network"}]'
# role bits as in cubectl's RoleMap: control 1, network 2, compute 4, storage 8, edge 16
BITS='{"control":1,"network":2,"compute":4,"storage":8,"control-network":3,"control-converged":15,"edge-core":29,"moderator":17}'
cubectl() {
    [ "$CUBECTL" = up ] || return 0   # cubectl node list prints nothing and exits 0 when it cannot load the list
    case "$*" in
        "node list -j") echo "$NODES" ;;
        "node list -r "*" -j") echo "$NODES" | jq -c --argjson b "$BITS" --arg r "$4" '[.[] | select(($b[.role] / $b[$r] | floor) % 2 == 1)]' ;;
        "node remove "*) echo "cubectl $*" >> "$T/calls" ;;
    esac
}
CUBECTL=up
is_sshable() { [ "$SSHABLE" = y ]; }
OPENSTACK=openstack_stub
openstack_stub() { case "$*" in "server list --all-projects --host"*) printf '%s' "$SERVERS" ;; esac; }
HEX_SDK=hexsdk_stub
hexsdk_stub() {
    case "$1" in
        ceph_host_remove_precheck) [ -z "$SHORT" ] || { echo "$SHORT" ; return 1 ; } ; return 0 ;;
    esac
    echo "$1" >> "$T/calls"
    [ "$1" != "$FAILING" ]
}
pcs() { case "$*" in "resource config cn1") return 0 ;; "resource delete"*) echo "pcs $*" >> "$T/calls" ;; *) return 1 ;; esac; }
cibadmin() { echo '<nodes><node id="cn1" uname="cn1" type="remote"/></nodes>'; }
crm_node() { echo "crm_node $*" >> "$T/calls"; }

run() {   # host, then: sshable servers short failing
    SSHABLE=$2 SERVERS=$3 SHORT=$4 FAILING=$5
    : > "$T/calls"
    cube_node_remove "$1" > "$T/out" 2> "$T/err"
    rc=$?
}
calls() { tr '\n' ';' < "$T/calls"; }

run cn1 n "" "" ""
chk "a shut-down compute node: every step in order, then it leaves the list" "$(calls)" \
    "os_segment_host_remove;os_nova_allocations_release;os_nova_service_remove;os_neutron_agent_remove;os_manila_service_remove;os_octavia_node_remove;ceph_osd_host_remove;pcs resource delete cn1;crm_node --force --remove cn1;cubectl node remove cn1;"
chk "  and succeeds" "$rc" "0"
chk "  reporting each step ok" "$(grep -c '^  ok  ' "$T/out")" "8"

run cn1 n "" "" os_nova_service_remove
chk "a failed step: the later steps still run, the node stays in the list" "$(calls)" \
    "os_segment_host_remove;os_nova_allocations_release;os_nova_service_remove;os_neutron_agent_remove;os_manila_service_remove;os_octavia_node_remove;ceph_osd_host_remove;pcs resource delete cn1;crm_node --force --remove cn1;"
chk "  and fails" "$rc" "1"
chk "  naming the step" "$(grep -c '^  FAILED  nova-compute service$' "$T/out")" "1"
chk "  and saying the node stays" "$(grep -c 'stays in the cluster' "$T/err")" "1"

run cn1 y "" "" ""
chk "a node that still answers: nothing is changed" "$(calls)" ""
chk "  it fails" "$rc" "1"
chk "  and says to shut it down" "$(grep -c 'shut it down first' "$T/err")" "1"

run cn1 n "abc-123 vm1" "" ""
chk "an instance left on the node: nothing is changed" "$(calls)$rc" "1"
chk "  and the instance is named" "$(grep -c 'abc-123 vm1' "$T/err")" "1"

run cn1 n "" "pool rbd needs 3 hosts, 2 would remain without cn1" ""
chk "ceph would be short of failure domains: nothing is changed" "$(calls)$rc" "1"
chk "  and the pool is named" "$(grep -c 'pool rbd needs 3 hosts' "$T/err")" "1"

run s1 n "" "" ""
chk "a storage node: ceph and pacemaker only, then it leaves the list" "$(calls)" "ceph_osd_host_remove;cubectl node remove s1;"
chk "  and succeeds" "$rc" "0"

for h in cc1 e1 m1 ; do
    run $h n "" "" ""
    chk "a node with the control role is refused: $h" "$(calls)$rc" "1"
done
chk "  saying so" "$(grep -c 'a node with the control role cannot be removed' "$T/err")" "1"
run n1 n "" "" ""
chk "a node without the compute role (network): ceph and pacemaker only" "$(calls)" "ceph_osd_host_remove;cubectl node remove n1;"
CUBECTL=down
run cn1 n "" "" ""
chk "roles that cannot be read: refused" "$(calls)$rc" "1"
CUBECTL=up
chk "the nodes the CLI offers: every node without the control role" "$(cube_data_node_list | tr '\n' ' ')" "cn1 cn10 s1 n1 "
run cn2 n "" "" ""
chk "a node that is not in the list is refused" "$(calls)$rc" "1"
NODES='[{"hostname":"cn10","role":"compute"}]'
run cn1 n "" "" ""
chk "cn1 is not taken for cn10" "$(calls)$rc" "1"

echo "test_cube_node_remove: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
