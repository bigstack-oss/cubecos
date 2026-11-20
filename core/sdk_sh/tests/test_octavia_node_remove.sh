#!/bin/bash
#
# Unit test for os_octavia_node_remove (../modules/sdk_os.sh), which cluster > remove_node uses: it
# deletes the removed node's octavia health-manager port by its name, which only the node itself
# ever deleted before, and fails when the port list cannot be read (cubecos#106).
#
# Self-contained: extracts the functions and answers their openstack calls from fixtures, so
# it needs no node.
#   Run: bash test_octavia_node_remove.sh   (exit 0 = pass)
#   SDK_OS_SH=<file> runs it against another copy of sdk_os.sh.
#
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="${SDK_OS_SH:-$DIR/../modules/sdk_os.sh}"
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT

for f in os_octavia_node_remove ; do
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
        "port list --name octavia-hmgr-port-cn1 -f value -c ID") echo p1 ;;
        *) echo "$*" >> "$T/calls" ;;
    esac
}
run() { : > "$T/calls"; "$@" > "$T/out" 2> "$T/err"; rc=$?; }
calls() { tr '\n' ';' < "$T/calls"; }

run os_octavia_node_remove cn1
chk "the node's health-manager port" "$rc $(calls)" "0 port delete p1;"
run os_octavia_node_remove cn2
chk "no port: nothing to do" "$rc $(calls)" "0 port list --name octavia-hmgr-port-cn2 -f value -c ID;"

DOWN=y
for f in "os_octavia_node_remove cn1" ; do
    run $f
    chk "an API that cannot be read fails ${f%% *}" "$rc" "1"
done

echo "test_octavia_node_remove: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
