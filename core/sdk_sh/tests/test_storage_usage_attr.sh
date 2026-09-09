#!/bin/bash
#
# Unit test for _storage_usage_os_maps / storage_usage_attribute
# (../modules/sdk_storage.sh).
#
# Neither `openstack volume list` nor `server list` exposes the owning project
# at any --long level, and `-c Project` is silently dropped, so attribution
# enumerates per project instead: one project list plus a server and volume
# list each. That also yields project_name and vm_name, which the kapacitor
# alert message interpolates and cannot be useful without.
#
# Three kinds attribute differently. An ephemeral disk is <instance_uuid>_disk
# [.local|.swap|.config], so the instance is in the name. A cinder volume
# carries its server in the attachment. An image in glance-images belongs to no
# VM and must attribute to null rather than guess, or a COW parent is charged
# to whichever clone was walked last. Pool rows pass through untouched.
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
M="$DIR/../modules/sdk_storage.sh"

SRVTO=60
for fn in _storage_usage_os_maps storage_usage_attribute ; do
    b="$(awk "/^$fn\\(\\)/{p=1} p{print} p&&/^}/{exit}" "$M")"
    [ -n "$b" ] || { echo "FAIL: $fn not extracted"; exit 1; }
    eval "$b"
done

pass=0 fail=0
chk(){ if [ "$2" = "$3" ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL: $1: got [$2] want [$3]"; fi; }
timeout(){ shift 3; "$@"; }

CALLS=$(mktemp)
openstack(){
    echo "$*" >> "$CALLS"
    case "$1 $2" in
    "project list") echo '[{"ID":"p1","Name":"appfw"},{"ID":"p2","Name":"demo"}]' ;;
    "server list")
        case "$*" in
        *"--project p1"*) echo '[{"ID":"vm-1","Name":"worker-a"}]' ;;
        *"--project p2"*) echo '[{"ID":"vm-2","Name":"rocky-b"}]' ;;
        esac ;;
    "volume list")
        case "$*" in
        *"--project p1"*) echo '[{"ID":"aaa","Attached to":[{"server_id":"vm-1"}]}]' ;;
        *"--project p2"*) echo '[{"ID":"ccc","Attached to":[]}]' ;;
        esac ;;
    esac
}

in='{"scope":"disk","pool":"cinder-volumes","disk_id":"volume-aaa","kind":"volume"}
{"scope":"disk","pool":"cinder-volumes","disk_id":"volume-ccc","kind":"volume"}
{"scope":"disk","pool":"ephemeral-vms","disk_id":"vm-2_disk","kind":"ephemeral"}
{"scope":"disk","pool":"ephemeral-vms","disk_id":"vm-2_disk.swap","kind":"ephemeral"}
{"scope":"disk","pool":"glance-images","disk_id":"img-9","kind":"image"}
{"scope":"pool","pool":"cinder-volumes","stored_bytes":5}
{"scope":"vm","instance_id":"vm-1","guest_used_bytes":9}
{"scope":"fs","instance_id":"vm-2","mountpoint":"/","used_percent":40}'

out="$(echo "$in" | storage_usage_attribute)"
get(){ echo "$out" | jq -r --arg d "$1" 'select(.disk_id==$d) | '"$2"; }

chk "row count"            "$(echo "$out" | grep -c .)"            "8"
chk "attached vol -> vm"   "$(get volume-aaa .instance_id)"        "vm-1"
chk "attached vol proj"    "$(get volume-aaa .project_id)"         "p1"
chk "attached vol projname" "$(get volume-aaa .project_name)"      "appfw"
chk "attached vol vm_name" "$(get volume-aaa .vm_name)"            "worker-a"
chk "detached vol vm"      "$(get volume-ccc .instance_id)"        "null"
chk "detached vol proj"    "$(get volume-ccc .project_id)"         "p2"
chk "ephemeral vm"         "$(get vm-2_disk .instance_id)"         "vm-2"
chk "ephemeral projname"   "$(get vm-2_disk .project_name)"        "demo"
chk "ephemeral vm_name"    "$(get vm-2_disk .vm_name)"             "rocky-b"
chk "suffixed ephemeral"   "$(get vm-2_disk.swap .instance_id)"    "vm-2"
chk "image vm null"        "$(get img-9 .instance_id)"             "null"
chk "image proj null"      "$(get img-9 .project_id)"              "null"
chk "pool row untouched"   "$(echo "$out" | jq -r 'select(.scope=="pool") | .stored_bytes')" "5"
chk "pool row got no instance_id" "$(echo "$out" | jq -r 'select(.scope=="pool") | has("instance_id")')" "false"
# guest rows must gain tenant/vm names -- the alert message interpolates them
chk "guest vm row projname" "$(echo "$out" | jq -r 'select(.scope=="vm") | .project_name')"  "appfw"
chk "guest vm row vm_name"  "$(echo "$out" | jq -r 'select(.scope=="vm") | .vm_name')"       "worker-a"
chk "guest fs row projname" "$(echo "$out" | jq -r 'select(.scope=="fs") | .project_name')"  "demo"
chk "guest fs row vm_name"  "$(echo "$out" | jq -r 'select(.scope=="fs") | .vm_name')"       "rocky-b"
chk "guest fs keeps pct"    "$(echo "$out" | jq -r 'select(.scope=="fs") | .used_percent')"  "40"
# one project list + one server list and one volume list per project, not per disk
chk "call count bounded"   "$(grep -c . "$CALLS")"                 "5"
rm -f "$CALLS"
echo "pass=$pass fail=$fail"; [ $fail -eq 0 ]
