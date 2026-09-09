#!/bin/bash
#
# Unit test for the collector orchestrator (../modules/sdk_storage.sh).
#
# Three properties matter and none are visible on a single-node lab:
#   1. Only the VIP-owning control node collects. is_vip_active() cannot say
#      that -- it reports the resource Started ANYWHERE, true on all three
#      control nodes -- so ownership is tested locally against the node name,
#      per the sdk_health.sh:975 idiom. No pacemaker at all (1cc) counts as
#      owner.
#   2. A run already in progress is skipped rather than stacked; a 20-minute
#      collection on a 15-minute timer would otherwise overlap forever.
#   3. Tag values are escaped. Influx line protocol treats an unescaped space,
#      comma or equals in a tag as a separator, which corrupts the point.
#
# Also: ceph df publishes no provisioned figure, so pool provisioned totals are
# summed from the disk rows already collected rather than a second rbd du pass.
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
M="$DIR/../modules/sdk_storage.sh"

for fn in _storage_usage_is_vip_owner _storage_usage_esc _storage_usage_line storage_usage_collect ; do
    b="$(awk "/^$fn\\(\\)/{p=1} p{print} p&&/^}/{exit}" "$M")"
    [ -n "$b" ] || { echo "FAIL: $fn not extracted"; exit 1; }
    eval "$b"
done
STORAGE_USAGE_LOCK=$(mktemp -u /tmp/suclock.XXXXXX)
TELEGRAF_DB=telegraf ; SRVSTO=10
timeout(){ shift 3; "$@"; }

pass=0 fail=0
chk(){ if [ "$2" = "$3" ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL: $1: got [$2] want [$3]"; fi; }

# --- guard
HOSTNAME=sky141
pcs(){ echo "  * vip	(ocf::heartbeat:IPaddr2):	 Started sky142"; }
_storage_usage_is_vip_owner; chk "not vip owner" "$?" "1"
pcs(){ echo "  * vip	(ocf::heartbeat:IPaddr2):	 Started sky141"; }
_storage_usage_is_vip_owner; chk "is vip owner" "$?" "0"
pcs(){ return 1; }
_storage_usage_is_vip_owner; chk "no pacemaker means owner" "$?" "0"

# --- escaping
chk "escape space"      "$(_storage_usage_esc 'my store')" 'my\ store'
chk "escape comma"      "$(_storage_usage_esc 'a,b')"      'a\,b'
chk "escape equals"     "$(_storage_usage_esc 'a=b')"      'a\=b'
chk "plain passthrough" "$(_storage_usage_esc 'sc01')"     'sc01'

# --- line protocol
rec='{"scope":"disk","backend":"my store","backend_type":"ceph","pool":"cinder-volumes","disk_id":"volume-a","kind":"volume","instance_id":"vm-1","project_id":"p1","confidence":"exact","provisioned_bytes":100,"allocated_bytes":25,"snapshot_bytes":5}'
line="$(echo "$rec" | _storage_usage_line storage_usage)"
chk "measurement"      "$(echo "$line" | cut -d, -f1)"                    "storage_usage"
chk "escaped tag"      "$(echo "$line" | grep -c 'backend=my\\ store')"   "1"
chk "instance tagged"  "$(echo "$line" | grep -c 'resource_id=vm-1')"     "1"
chk "disk_id is field" "$(echo "$line" | grep -c 'disk_id="volume-a"')"   "1"
chk "int suffix"       "$(echo "$line" | grep -c 'allocated_bytes=25i')"  "1"
chk "thin ratio"       "$(echo "$line" | grep -c 'thin_ratio=4')"         "1"
line2="$(echo "$rec" | jq -c '.instance_id=null' | _storage_usage_line storage_usage)"
chk "null tag omitted" "$(echo "$line2" | grep -c 'resource_id=')"        "0"
rec3='{"scope":"disk","backend":"b","disk_id":"d","provisioned_bytes":null,"allocated_bytes":null}'
l3="$(echo "$rec3" | _storage_usage_line storage_usage)"
chk "null fields omitted" "$(echo "$l3" | grep -c 'allocated_bytes')"     "0"
chk "no thin ratio on null" "$(echo "$l3" | grep -c 'thin_ratio')"        "0"

# --- orchestration
HOSTNAME=sky141; pcs(){ echo " Started sky141"; }
CALLS=$(mktemp); LINES=$(mktemp); POOLS=$(mktemp)
# vm-1 has a guest agent; vm-2 has a disk but no guest reading at all
rec2='{"scope":"disk","backend":"b","backend_type":"ceph","pool":"cinder-volumes","disk_id":"volume-b","kind":"volume","instance_id":"vm-2","project_id":"p1","project_name":"proj","vm_name":"db-01","confidence":"exact","provisioned_bytes":200,"allocated_bytes":180,"snapshot_bytes":0}'
storage_usage_ceph_disks(){ echo "$rec"; echo "$rec2"; }
storage_usage_nfs_disks(){ :; }
storage_usage_ceph_pools(){ echo '{"scope":"pool","backend":"CubeStorage","backend_type":"ceph","pool":"cinder-volumes","capacity_bytes":1000,"stored_bytes":25,"raw_used_bytes":75,"provisioned_bytes":null}'; }
storage_usage_cinder_pools(){ :; }
storage_usage_guest_disks(){ echo '{"scope":"vm","instance_id":"vm-1","guest_total_bytes":10,"guest_used_bytes":4,"fs_count":1,"confidence":"exact"}'
                             echo '{"scope":"fs","instance_id":"vm-1","mountpoint":"/","device":"vda1","fs_total_bytes":10,"fs_used_bytes":4,"used_percent":40,"confidence":"exact"}'; }
storage_usage_attribute(){ cat; }
storage_usage_thresholds(){ cat > "$POOLS"; }
Debug(){ :; }
# the collector prints line protocol on stdout for telegraf to deliver, so the
# test captures stdout rather than mocking a writer
# the prometheus half: without this the call is an undefined command, the test
# still reports pass, and a broken textfile path ships unnoticed
TEXTFILE=$(mktemp)
_storage_usage_textfile(){ cat >> "$TEXTFILE"; }

storage_usage_collect > "$LINES"
# telegraf delivers what the collector prints, so nothing here may post to a
# database directly -- and nothing may go to monasca, which is retired (#672)
chk "no direct influx write" "$(grep -c '8086\|9092' "$LINES")" "0"
chk "nothing to monasca"     "$(grep -c monasca "$LINES")"      "0"
chk "disk row emitted"   "$(grep -c 'storage_usage,' "$LINES")"        "2"
chk "pool row emitted"   "$(grep -c 'storage_pool_usage,' "$LINES")"   "1"
chk "guest vm row emitted" "$(grep -c 'storage_usage_guest,' "$LINES")" "1"
# one alarm point per thing that can fill up: vm-1's filesystem from the guest,
# vm-2's disk from the block layer. Without the fallback vm-2 raises no disk
# alarm at all and nothing says so.
chk "alarm points"        "$(grep -c 'vm.disk.usage_perc,' "$LINES")"                                 "2"
chk "guest row tagged"    "$(grep -c 'resource_id=vm-1,mountpoint=/,source=guest,' "$LINES")"         "1"
chk "guest row value"     "$(grep -c 'resource_id=vm-1,mountpoint=/,source=guest.* value=40i$' "$LINES")" "1"
# the fallback names the disk in the field the alarm groups and reports on
chk "block row tagged"    "$(grep -c 'resource_id=vm-2,mountpoint=volume-b,source=block,' "$LINES")"   "1"
# 180 of 200 provisioned
chk "block row percent"   "$(grep -c 'resource_id=vm-2,.*source=block.* value=90i$' "$LINES")"        "1"
# a disk that already has a guest reading must not also alarm from the block
# layer -- the two measure different things and it would alarm twice
chk "no block beside guest" "$(grep -c 'resource_id=vm-1.*source=block' "$LINES")" "0"
chk "pool provisioned derived from disks" "$(jq -r .provisioned_bytes "$POOLS")" "300"
chk "lock released"      "$([ -e "$STORAGE_USAGE_LOCK" ] && echo held || echo free)" "free"

# every line must reach the writer, not just the first
chk "all telegraf lines written" "$(grep -cE '^storage_(usage|pool_usage|usage_guest),' "$LINES")" "4"
# every scope must reach the prometheus emitter, or a panel goes blank with no
# error anywhere
chk "textfile got the disk row"  "$(jq -r 'select(.scope=="disk")'  < "$TEXTFILE" | grep -c disk_id)"      "2"
chk "textfile got the pool row"  "$(jq -r 'select(.scope=="pool")'  < "$TEXTFILE" | grep -c capacity_bytes)" "1"
chk "textfile got the vm row"    "$(jq -r 'select(.scope=="vm")'    < "$TEXTFILE" | grep -c instance_id)"  "1"
chk "textfile got the fs row"    "$(jq -r 'select(.scope=="fs")'    < "$TEXTFILE" | grep -c mountpoint)"   "1"

L1=$(mktemp); mkdir -p "$STORAGE_USAGE_LOCK"; echo $$ > "$STORAGE_USAGE_LOCK/pid"
storage_usage_collect > "$L1"
chk "skipped while locked" "$(grep -c . "$L1")" "0"
rm -rf "$STORAGE_USAGE_LOCK" "$L1" 2>/dev/null

: > "$CALLS"; pcs(){ echo " Started sky142"; }
storage_usage_collect
chk "non-owner collects nothing" "$(grep -c . "$CALLS")" "0"

rm -f "$CALLS" "$LINES" "$POOLS" "$TEXTFILE"

# --- lock recovery, last so the extra runs cannot disturb the assertions above
# an earlier block left this node a non-owner, which returns before the lock
pcs(){ echo " Started sky141"; }
L2=$(mktemp)
# a run killed before it can clean up (telegraf timeout, SIGPIPE, SIGKILL)
# leaves the lock behind; the next run must take it over, not go quiet forever
mkdir -p "$STORAGE_USAGE_LOCK"; echo 999999 > "$STORAGE_USAGE_LOCK/pid"
storage_usage_collect > "$L2"
chk "stale lock taken over" "$(grep -c 'vm.disk.usage_perc,' "$L2")"                        "2"
chk "lock released again"   "$([ -e "$STORAGE_USAGE_LOCK" ] && echo held || echo free)"     "free"

# a lock whose holder is alive must still be respected
mkdir -p "$STORAGE_USAGE_LOCK"; echo $$ > "$STORAGE_USAGE_LOCK/pid"
storage_usage_collect > "$L2"
chk "live lock respected"   "$(grep -c . "$L2")"                                            "0"
rm -rf "$STORAGE_USAGE_LOCK" "$L2"

echo "pass=$pass fail=$fail"; [ $fail -eq 0 ]
