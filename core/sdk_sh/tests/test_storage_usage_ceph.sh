#!/bin/bash
#
# Unit test for storage_usage_ceph_disks and storage_usage_ceph_pools
# (../modules/sdk_storage.sh).
#
# rbd du reports one row per image plus one row per snapshot; the head row is
# the only one carrying provisioned_size, and snapshot rows must be summed
# separately rather than added to the image's own footprint. librbd warns on
# stderr when an image's fast-diff map is invalid, in which case used_size came
# from a full scan or is stale -- those images report "estimated", not "exact".
#
# ceph df detail carries no provisioned figure at all, so pool rows omit it and
# the orchestrator fills it in from the disk rows. reduction_ratio must be null
# when compression never engaged: a 1.0 would read as "compression on, saving
# nothing", which is a different and wrong statement.
#
# Self-contained: extracts the functions and mocks rbd/ceph/timeout, so it needs
# no cluster and no ceph. Run: bash test_storage_usage_ceph.sh
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
M="$DIR/../modules/sdk_storage.sh"

SRVTO=60
SRVSTO=10
CEPH="ceph"
for fn in storage_usage_ceph_disks storage_usage_ceph_pools ; do
    b="$(awk "/^$fn\\(\\)/{p=1} p{print} p&&/^}/{exit}" "$M")"
    [ -n "$b" ] || { echo "FAIL: $fn not extracted"; exit 1; }
    eval "$b"
done
STORAGE_USAGE_CEPH_POOLS="$(awk -F'"' '/^STORAGE_USAGE_CEPH_POOLS=/{print $2}' "$M")"
[ -n "$STORAGE_USAGE_CEPH_POOLS" ] || { echo "FAIL: pool list not extracted"; exit 1; }

pass=0 fail=0
chk(){ if [ "$2" = "$3" ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL: $1: got [$2] want [$3]"; fi; }

timeout(){ shift 3; "$@"; }   # strip -k 5 <secs>

# cinder-volumes: one image with a snapshot. ephemeral-vms: one image whose
# fast-diff map is invalid. Other pools empty.
rbd(){
    local pool=""
    while [ $# -gt 0 ]; do case "$1" in -p) pool=$2; shift 2;; *) shift;; esac; done
    case "$pool" in
    cinder-volumes)
        echo '{"images":[
          {"name":"volume-aaa","provisioned_size":10737418240,"used_size":2147483648},
          {"name":"volume-aaa","snapshot":"snap1","used_size":536870912}]}' ;;
    ephemeral-vms)
        echo "warning: fast diff map is invalid for ephemeral-vms/bbb_disk. operation may be slow." >&2
        echo '{"images":[{"name":"bbb_disk","provisioned_size":21474836480,"used_size":5368709120}]}' ;;
    *)  echo '{"images":[]}' ;;
    esac
}

out="$(storage_usage_ceph_disks)"
get(){ echo "$out" | jq -r --arg d "$1" 'select(.disk_id==$d) | '"$2"; }

chk "record count"        "$(echo "$out" | grep -c .)"                  "2"
chk "volume provisioned"  "$(get volume-aaa .provisioned_bytes)"        "10737418240"
chk "volume allocated"    "$(get volume-aaa .allocated_bytes)"          "2147483648"
chk "snapshot summed"     "$(get volume-aaa .snapshot_bytes)"           "536870912"
chk "volume kind"         "$(get volume-aaa .kind)"                     "volume"
chk "volume confidence"   "$(get volume-aaa .confidence)"               "exact"
chk "ephemeral kind"      "$(get bbb_disk .kind)"                       "ephemeral"
chk "invalid fast-diff"   "$(get bbb_disk .confidence)"                 "estimated"
chk "ephemeral snapshots" "$(get bbb_disk .snapshot_bytes)"             "0"
chk "backend_type"        "$(get volume-aaa .backend_type)"             "ceph"
chk "backend"             "$(get volume-aaa .backend)"                  "CubeStorage"
chk "pool tagged"         "$(get bbb_disk .pool)"                       "ephemeral-vms"
chk "scope"               "$(get volume-aaa .scope)"                    "disk"

# --- pools: 3x replication, compression active on one pool only
ceph(){
    cat <<'JSON'
{"stats":{"total_bytes":3000000000000,"total_used_bytes":900000000000},
 "pools":[
  {"name":"cinder-volumes","stats":{"stored":100000000000,"bytes_used":300000000000,
     "max_avail":500000000000,"compress_under_bytes":40000000000,"compress_bytes_used":10000000000}},
  {"name":"glance-images","stats":{"stored":10000000000,"bytes_used":30000000000,
     "max_avail":500000000000,"compress_under_bytes":0,"compress_bytes_used":0}},
  {"name":"unrelated-pool","stats":{"stored":5,"bytes_used":15,"max_avail":1}}]}
JSON
}

pout="$(storage_usage_ceph_pools)"
pget(){ echo "$pout" | jq -r --arg p "$1" 'select(.pool==$p) | '"$2"; }

chk "pool rows"           "$(echo "$pout" | grep -c .)"                 "2"
chk "unlisted pool skipped" "$(pget unrelated-pool .pool)"              ""
chk "stored"              "$(pget cinder-volumes .stored_bytes)"        "100000000000"
chk "raw used"            "$(pget cinder-volumes .raw_used_bytes)"      "300000000000"
chk "replication factor"  "$(pget cinder-volumes .replication_factor)"  "3"
chk "reduction ratio"     "$(pget cinder-volumes .reduction_ratio)"     "4"
chk "no compression null" "$(pget glance-images .reduction_ratio)"      "null"
chk "no-compr confidence" "$(pget glance-images .confidence)"           "unavailable"
chk "compr confidence"    "$(pget cinder-volumes .confidence)"          "exact"
chk "pool scope"          "$(pget cinder-volumes .scope)"               "pool"
chk "no provisioned yet"  "$(pget cinder-volumes .provisioned_bytes)"   "null"

echo "pass=$pass fail=$fail"; [ $fail -eq 0 ]
