#!/bin/bash
#
# Unit test for the nova, neutron and masakari steps of cluster > remove_node (../modules/sdk_os.sh):
#   os_nova_allocations_release: removes only the removed node's provider from each consumer
#     (never `allocation delete`, which would drop an evacuated instance's allocation on its
#     new host too), and refuses an instance that is still on the node (cubecos#2423)
#   os_neutron_agent_remove: without a binary, deletes every agent of the host
#   os_segment_host_remove: deletes the host from the masakari segments that list it (cubecos#2423)
#   and each fails when the API it reads fails.
#
# Self-contained: extracts the functions and answers their openstack calls from fixtures, so
# it needs no node.
#   Run: bash test_sdk_os_node_remove.sh   (exit 0 = pass)
#   SDK_OS_SH=<file> runs it against another copy of sdk_os.sh.
#
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="${SDK_OS_SH:-$DIR/../modules/sdk_os.sh}"
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT

for f in os_nova_allocations_release os_neutron_agent_remove os_segment_host_remove ; do
    body="$(awk "/^$f\(\)/{p=1} p{print} p&&/^}/{exit}" "$SRC")"
    [ -n "$body" ] || { echo "FAIL: $f not extracted"; exit 1; }
    eval "$body"
done

pass=0 fail=0
chk() { if [ "$2" = "$3" ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL: $1: got [$2] want [$3]"; fi; }

OPENSTACK=os_stub
DOWN=n
os_stub() {
    [ "$DOWN" = n ] || return 1
    case "$*" in
        "resource provider list --name cn1 -f value -c uuid") echo rp-cn1 ;;
        "resource provider list --name cn2 -f value -c uuid") ;;
        "--os-placement-api-version 1.28 resource provider show rp-cn1 --allocations -f json") echo "$ALLOC" ;;
        "server show vm-a -f value -c OS-EXT-SRV-ATTR:host") echo cc2 ;;
        "server show vm-b -f value -c OS-EXT-SRV-ATTR:host") echo cn1 ;;
        "server show "*) return 1 ;;
        "network agent list --host cn1 -f value -c ID") printf '%s\n' a1 a2 a3 ;;
        "network agent list --host cn1 --binary ovn-controller -f value -c ID") echo a1 ;;
        "segment list -f value -c uuid") printf '%s\n' seg1 seg2 ;;
        "segment host list seg1 -f value -c name") printf '%s\n' cn10 cc1 ;;
        "segment host list seg2 -f value -c name") printf '%s\n' cn1 cc1 ;;
        *) echo "$*" >> "$T/calls" ;;
    esac
}
run() { : > "$T/calls"; "$@" > "$T/out" 2> "$T/err"; rc=$?; }
calls() { tr '\n' ';' < "$T/calls"; }

ALLOC='{"allocations":{"vm-a":{"resources":{"VCPU":1}},"mig-c":{"resources":{"VCPU":1}}}}'
run os_nova_allocations_release cn1
chk "evacuated instance and stale consumer: only this provider's part is removed" "$rc $(calls)" \
    "0 --os-placement-api-version 1.28 resource provider allocation unset --provider rp-cn1 mig-c;--os-placement-api-version 1.28 resource provider allocation unset --provider rp-cn1 vm-a;"
chk "  never the consumer's whole allocation" "$(grep -c 'allocation delete' "$T/calls")" "0"
ALLOC='{"allocations":{"vm-b":{"resources":{"VCPU":1}}}}'
run os_nova_allocations_release cn1
chk "an instance still on the node: refused, nothing released" "$rc $(calls)" "1 "
ALLOC='{"allocations":{}}'
run os_nova_allocations_release cn1
chk "no allocation left: nothing to do" "$rc $(calls)" "0 "
run os_nova_allocations_release cn2
chk "no provider: nothing to do" "$rc $(calls)" "0 "

run os_neutron_agent_remove cn1
chk "neutron: every agent of the host" "$rc $(calls)" "0 network agent delete a1;network agent delete a2;network agent delete a3;"
run os_neutron_agent_remove cn1 ovn-controller
chk "neutron: one binary when given" "$rc $(calls)" "0 network agent delete a1;"

run os_segment_host_remove cn1
chk "masakari: only the segment that lists cn1" "$rc $(calls)" "0 segment host delete seg2 cn1;"


DOWN=y
for f in "os_nova_allocations_release cn1" "os_neutron_agent_remove cn1" "os_segment_host_remove cn1" ; do
    run $f
    chk "an API that cannot be read fails ${f%% *}" "$rc" "1"
done

echo "test_sdk_os_node_remove: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
