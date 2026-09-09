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
chk "instance tagged"  "$(echo "$line" | grep -c 'instance_id=vm-1')"     "1"
chk "disk_id is field" "$(echo "$line" | grep -c 'disk_id="volume-a"')"   "1"
chk "int suffix"       "$(echo "$line" | grep -c 'allocated_bytes=25i')"  "1"
chk "thin ratio"       "$(echo "$line" | grep -c 'thin_ratio=4')"         "1"
line2="$(echo "$rec" | jq -c '.instance_id=null' | _storage_usage_line storage_usage)"
chk "null tag omitted" "$(echo "$line2" | grep -c 'instance_id=')"        "0"
rec3='{"scope":"disk","backend":"b","disk_id":"d","provisioned_bytes":null,"allocated_bytes":null}'
l3="$(echo "$rec3" | _storage_usage_line storage_usage)"
chk "null fields omitted" "$(echo "$l3" | grep -c 'allocated_bytes')"     "0"
chk "no thin ratio on null" "$(echo "$l3" | grep -c 'thin_ratio')"        "0"

# --- orchestration
HOSTNAME=sky141; pcs(){ echo " Started sky141"; }
CALLS=$(mktemp); LINES=$(mktemp); POOLS=$(mktemp)
storage_usage_ceph_disks(){ echo "$rec"; }
storage_usage_nfs_disks(){ :; }
storage_usage_ceph_pools(){ echo '{"scope":"pool","backend":"CubeStorage","backend_type":"ceph","pool":"cinder-volumes","capacity_bytes":1000,"stored_bytes":25,"raw_used_bytes":75,"provisioned_bytes":null}'; }
storage_usage_cinder_pools(){ :; }
storage_usage_guest_disks(){ echo '{"scope":"vm","instance_id":"vm-1","guest_total_bytes":10,"guest_used_bytes":4,"fs_count":1,"confidence":"exact"}'
                             echo '{"scope":"fs","instance_id":"vm-1","mountpoint":"/","device":"vda1","fs_total_bytes":10,"fs_used_bytes":4,"used_percent":40,"confidence":"exact"}'; }
storage_usage_attribute(){ cat; }
storage_usage_thresholds(){ cat > "$POOLS"; }
Debug(){ :; }
# the real writer POSTs bulk line protocol; a multi-line INSERT would drop all
# but the first line, so the mock records every line it is handed
_storage_usage_influx_write(){ echo "$1" >> "$CALLS"; cat >> "$LINES"; }

storage_usage_collect
# monasca is retired (cubecos#672): both the GUI rows and the alarm series
# land in telegraf.def, written through the kapacitor proxy
chk "both writes telegraf" "$(grep -c telegraf "$CALLS")" "2"
chk "nothing to monasca"   "$(grep -c monasca "$CALLS")"  "0"
chk "disk row emitted"   "$(grep -c 'storage_usage,' "$LINES")"        "1"
chk "pool row emitted"   "$(grep -c 'storage_pool_usage,' "$LINES")"   "1"
chk "guest vm row emitted" "$(grep -c 'storage_usage_guest,' "$LINES")" "1"
chk "monasca fs metric"  "$(grep -c 'vm.disk.usage_perc,' "$LINES")"   "1"
chk "fs metric has resource_id" "$(grep -c 'resource_id=vm-1' "$LINES")" "1"
chk "pool provisioned derived from disks" "$(jq -r .provisioned_bytes "$POOLS")" "100"
chk "lock released"      "$([ -e "$STORAGE_USAGE_LOCK" ] && echo held || echo free)" "free"
# every line must reach the writer, not just the first
chk "all telegraf lines written" "$(grep -cE '^storage_(usage|pool_usage|usage_guest),' "$LINES")" "3"

: > "$CALLS"; mkdir -p "$STORAGE_USAGE_LOCK"
storage_usage_collect
chk "skipped while locked" "$(grep -c . "$CALLS")" "0"
rmdir "$STORAGE_USAGE_LOCK"

: > "$CALLS"; pcs(){ echo " Started sky142"; }
storage_usage_collect
chk "non-owner collects nothing" "$(grep -c . "$CALLS")" "0"

rm -f "$CALLS" "$LINES" "$POOLS"
echo "pass=$pass fail=$fail"; [ $fail -eq 0 ]
